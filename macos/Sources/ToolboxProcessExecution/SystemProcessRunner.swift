import Foundation
import Darwin
import ToolboxConcurrency

/// Synchronous boundary: call only from a dedicated blocking worker. All descriptors and buffers
/// have one owner. No Foundation Process callbacks, concurrent Data mutations or blocking waitpid.
package enum SystemProcessRunner {
    private static let captureLimit = 16 * 1024 * 1024 // per stream; continue draining after the cap
    package static func run(_ request: CommandRequest) -> ProcessResult {
        if request.cancellation.isCancelled { return .cancelled }
        guard request.timeout.isFinite, request.timeout > 0 else {
            return ProcessResult(exitCode: -1, outcome: .timedOut)
        }
        guard !request.executable.utf8.contains(0), !request.arguments.contains(where: { $0.utf8.contains(0) }),
              !request.serverPort.utf8.contains(0) else { return failure(EINVAL) }
        let started = ContinuousClock.now
        let deadline = started.advanced(by: .seconds(request.timeout))
        var out: [Int32] = [0, 0], err: [Int32] = [0, 0]
        guard pipe(&out) == 0 else { return failure(errno) }
        guard pipe(&err) == 0 else { let code = errno; out.forEach { close($0) }; return failure(code) }
        // Only the child write ends are dup'd to stdout/stderr. Never inherit other owned FDs.
        for fd in out + err { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        var setup = posix_spawn_file_actions_init(&actions)
        guard setup == 0 else { (out + err).forEach { close($0) }; return failure(setup) }
        defer { posix_spawn_file_actions_destroy(&actions) }
        setup = posix_spawnattr_init(&attributes)
        guard setup == 0 else { (out + err).forEach { close($0) }; return failure(setup) }
        defer { posix_spawnattr_destroy(&attributes) }
        let configuration = [
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0),
            posix_spawn_file_actions_adddup2(&actions, out[1], STDOUT_FILENO),
            posix_spawn_file_actions_adddup2(&actions, err[1], STDERR_FILENO),
            posix_spawnattr_setpgroup(&attributes, 0),
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        ]
        if let code = configuration.first(where: { $0 != 0 }) {
            (out + err).forEach { close($0) }; return failure(code)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["ANDROID_ADB_SERVER_PORT"] = request.serverPort
        let argv = ([request.executable] + request.arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var pid: pid_t = 0
        let spawnCode = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                posix_spawn(&pid, request.executable, &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        close(out[1]); close(err[1])
        guard spawnCode == 0 else { close(out[0]); close(err[0]); return failure(spawnCode) }
        var descriptors = [out[0], err[0]]
        defer { descriptors.filter { $0 >= 0 }.forEach { close($0) } }
        for fd in descriptors { _ = fcntl(fd, F_SETFL, O_NONBLOCK) }
        var data = [Data(), Data()], truncated = false
        var status: Int32 = 0
        var ownsChild = true
        var outcome: ProcessResult.Outcome?
        var terminationTime: ContinuousClock.Instant?
        var exitedAt: ContinuousClock.Instant?
        var killed = false
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let now = ContinuousClock.now
            if outcome == nil {
                if request.cancellation.isCancelled { outcome = .cancelled }
                else if now >= deadline { outcome = .timedOut }
                }
            if outcome != nil, terminationTime == nil {
                terminationTime = now; _ = kill(-pid, SIGTERM)
            }
            if let terminationTime, !killed, now >= terminationTime.advanced(by: .milliseconds(150)) {
                _ = kill(-pid, SIGKILL); killed = true
            }
            if exitedAt == nil {
                // Observe without reaping: retaining the waitable child reserves its PID while
                // we may still signal its process group. Never signal a potentially reused PID.
                var info = siginfo_t()
                let waited = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT)
                if waited == 0, info.si_pid == pid { exitedAt = now }
                else if waited < 0, errno != EINTR {
                    outcome = outcome ?? .ioFailure(errno)
                    if errno == ECHILD { ownsChild = false }
                    break
                }
            }
            // Fair, bounded draining: a child producing forever cannot delay the deadline check.
            for index in descriptors.indices where descriptors[index] >= 0 {
                for _ in 0..<16 {
                    let count = read(descriptors[index], &buffer, buffer.count)
                    if count > 0 {
                        let keep = min(count, max(0, captureLimit - data[index].count))
                        data[index].append(contentsOf: buffer.prefix(keep))
                        if keep < count { truncated = true }
                    } else if count == 0 {
                        close(descriptors[index]); descriptors[index] = -1; break
                    } else if errno == EAGAIN || errno == EWOULDBLOCK { break }
                    else if errno != EINTR {
                        outcome = outcome ?? .ioFailure(errno)
                        close(descriptors[index]); descriptors[index] = -1; break
                    }
                }
            }
            if exitedAt != nil && descriptors.allSatisfy({ $0 < 0 }) && (outcome == nil || killed) { break }
            // A descendant can retain both pipes after its parent exits. Never wait for its EOF.
            if let exitedAt, now >= exitedAt.advanced(by: .milliseconds(200)) {
                _ = kill(-pid, SIGKILL); break
            }
            if let terminationTime, now >= terminationTime.advanced(by: .milliseconds(500)) { break }
            var polls = descriptors.filter { $0 >= 0 }.map { pollfd(fd: $0, events: Int16(POLLIN | POLLHUP), revents: 0) }
            _ = poll(&polls, nfds_t(polls.count), 10)
        }
        if ownsChild {
            if outcome != nil { _ = kill(-pid, SIGKILL) }
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == 0 || (waited < 0 && errno == EINTR) {
                _ = kill(-pid, SIGKILL)
                // No unbounded wait after the caller's deadline, including kernel-delayed exits.
                reapLater(pid)
            } else if waited < 0 { outcome = outcome ?? .ioFailure(errno) }
        }
        let signal = status & 0x7f
        let exitCode = outcome == nil ? (signal == 0 ? (status >> 8) & 0xff : 128 + signal) : -1
        return ProcessResult(standardOutput: String(decoding: data[0], as: UTF8.self),
            standardError: String(decoding: data[1], as: UTF8.self), exitCode: exitCode,
            outcome: outcome ?? (signal == 0 ? .exited : .signalled(signal)), outputTruncated: truncated)
    }
    private static let reaper = DispatchQueue(label: "com.mimonitor.toolbox.process-reaper", qos: .utility)
    private static func reapLater(_ pid: pid_t) {
        reaper.asyncAfter(deadline: .now() + .milliseconds(100)) {
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == 0 || (result < 0 && errno == EINTR) { reapLater(pid) }
        }
    }
    private static func failure(_ code: Int32) -> ProcessResult {
        ProcessResult(standardError: "执行失败: \(String(cString: strerror(code)))", exitCode: -1, outcome: .launchFailed(code))
    }
}
