import ToolboxConcurrency
import ToolboxProcessExecution
import ToolboxDomain
import ToolboxApplication
import Foundation
import Darwin

/// 内网扫描（macOS 实现）。
/// 通过 ifconfig 取本机网段，
/// 再对 5555 端口做 TCP 探测。
enum NetworkScan {
    /// 探测 host:port 是否可连。
    ///
    /// 注意：这里**必须**用「非阻塞 connect + poll」，不能用 `SO_SNDTIMEO`。
    /// macOS 上 SO_SNDTIMEO 不约束 connect()：连一个不存在的主机时，内核会一直等
    /// ARP 解析超时（可长达 75 秒以上）才返回。扫描一个 /24 网段时绝大多数地址都是
    /// 不存在的主机，用阻塞 connect 会把线程池占满，导致真正在线的设备排不上调度，
    /// 最终「什么都扫不到」。
    static func isTcpOpen(host: String, port: Int, timeout: Double = 0.4,
                          cancellation: CommandCancellation = CommandCancellation()) -> Bool {
        guard (1...65535).contains(port), timeout.isFinite, timeout > 0, !cancellation.isCancelled else { return false }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        // 切到非阻塞
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else { return false }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr(host))

        let ret = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if ret == 0 { return true }                 // 立刻连上（本机/已缓存 ARP）
        guard errno == EINPROGRESS else { return false }

        // Poll in short slices so cancellation never waits for the full socket timeout.
        let end = ContinuousClock.now.advanced(by: .seconds(timeout))
        while !cancellation.isCancelled, ContinuousClock.now < end {
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&pfd, 1, 20)
            if ready < 0 { if errno == EINTR { continue }; return false }
            guard ready > 0 else { continue }
            var error: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            return getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0 && error == 0
        }
        return false
    }

    /// 扫描本机所在网段中开放了指定端口的设备。
    /// 用信号量限制并发，避免一次性铺开 254×N 个线程。
    static func scan(port: Int = 5555, timeout: Double = 0.4, maxConcurrent: Int = 128,
                     cancellation: CommandCancellation = CommandCancellation(),
                     subnets suppliedSubnets: [String]? = nil, budget: TimeInterval = 15,
                     probe: @escaping (String, Int, Double, CommandCancellation) -> Bool = {
                         isTcpOpen(host: $0, port: $1, timeout: $2, cancellation: $3)
                     }) -> [String] {
        guard maxConcurrent > 0, budget.isFinite, budget > 0, !cancellation.isCancelled else { return [] }
        let deadline = ContinuousClock.now.advanced(by: .seconds(budget))
        // 不再 `.prefix(2)` 截断：多网卡时显示器可能在第三个网段上。
        // 上限 4 是防御性的 —— 网卡特别多时别把扫描拖太久。
        let subnets = Array((suppliedSubnets ?? localIPv4Subnets(cancellation: cancellation)).prefix(4))
        var targets: [String] = []
        for subnet in subnets {
            for host in 1...254 {
                targets.append("\(subnet).\(host)")
            }
        }
        guard !targets.isEmpty else { return [] }

        let found = ScanResults()
        let token = CommandCancellation(parent: cancellation)
        defer { token.cancel() }
        let semaphore = DispatchSemaphore(value: maxConcurrent)
        let group = DispatchGroup()
        targetsLoop: for ip in targets {
            while semaphore.wait(timeout: .now() + .milliseconds(20)) != .success {
                if token.isCancelled || ContinuousClock.now >= deadline { break targetsLoop }
            }
            if token.isCancelled || ContinuousClock.now >= deadline { semaphore.signal(); break }
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { semaphore.signal(); group.leave() }
                guard !token.isCancelled else { return }
                if probe(ip, port, timeout, token), !token.isCancelled { found.append(ip) }
            }
        }
        while group.wait(timeout: .now() + .milliseconds(20)) != .success {
            if token.isCancelled || ContinuousClock.now >= deadline { break }
        }
        // Lock-protected snapshot remains safe even if a cancelled probe is still returning.
        return found.snapshot().sorted { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    private final class ScanResults {
        private let lock = NSLock()
        private var values: [String] = []
        func append(_ value: String) { lock.lock(); defer { lock.unlock() }; values.append(value) }
        func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return values }
    }

    /// 解析本机**真实局域网**网段（前三段，去重）。
    ///
    /// 返回全部符合条件的网段，不再只取前两个 —— 多网卡（有线 + 无线）时
    /// 显示器可能在任意一个上，截断会直接漏掉。
    ///
    /// 会跳过这几类，它们在 `ifconfig` 里都长得像正常 IPv4，但都不是"能放显示器的局域网"：
    ///   - 回环 `127/8`
    ///   - 自分配地址 `169.254/16`（没拿到 DHCP 时的兜底地址）
    ///   - **点对点隧道** —— 行里有 `-->` 就是（`utun*` / `ipsec*` / `ppp*` 都是这种）。
    ///     开着 Clash / Surge 这类代理工具时会插入 `utun` 接口
    ///   - **代理工具的 fake-IP 段** `198.18.0.0/15`（RFC 2544 保留段，真实局域网不会用）
    ///
    /// 不处理这些的话，代理环境下会去扫一个根本不存在设备的隧道网段，
    /// 既浪费时间，又可能因为占满并发名额而漏掉真正的那个网段。
    static func localIPv4Subnets(cancellation: CommandCancellation = CommandCancellation(),
                                 execute: (CommandRequest) -> ProcessResult = SystemProcessRunner.run) -> [String] {
        let result = execute(CommandRequest(executable: "/sbin/ifconfig", arguments: [], serverPort: "0",
                                           timeout: 3, cancellation: cancellation))
        return result.succeeded ? parseSubnets(result.standardOutput) : []
    }

    static func ping(host: String, cancellation: CommandCancellation = CommandCancellation(),
                     execute: (CommandRequest) -> ProcessResult = SystemProcessRunner.run) -> Bool {
        execute(CommandRequest(executable: "/sbin/ping", arguments: ["-c", "1", "-W", "1000", host],
                               serverPort: "0", timeout: 2, cancellation: cancellation)).succeeded
    }

    static func parseSubnets(_ text: String) -> [String] {
        var subnets: [String] = []
        var currentInterface = ""

        for line in text.split(separator: "\n") {
            // 不以空白开头的行是网卡标题，形如 "en0: flags=8863<...>"
            if let first = line.first, !first.isWhitespace {
                currentInterface = String(line.prefix(while: { $0 != ":" })).lowercased()
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("inet ") else { continue }
            // 点对点隧道：inet 198.18.0.1 --> 198.18.0.1 netmask ...
            guard !trimmed.contains("-->") else { continue }

            let parts = trimmed.split(separator: " ")
            guard parts.count >= 2 else { continue }
            let octets = parts[1].split(separator: ".")
            guard octets.count == 4 else { continue }
            guard let o0 = Int(octets[0]), let o1 = Int(octets[1]), let o2 = Int(octets[2]) else { continue }

            if o0 == 127 { continue }                                  // 回环
            if o0 == 169 && o1 == 254 { continue }                     // 自分配地址
            if o0 == 198 && (o1 == 18 || o1 == 19) { continue }        // 代理 fake-IP 段

            // 隧道 / 虚拟网卡（有些系统上它们不带 -->）
            let tunnelPrefixes = ["utun", "ipsec", "ppp", "gif", "stf", "awdl", "llw", "bridge"]
            if tunnelPrefixes.contains(where: { currentInterface.hasPrefix($0) }) { continue }

            let subnet = "\(o0).\(o1).\(o2)"
            if !subnets.contains(subnet) { subnets.append(subnet) }
        }
        return subnets
    }
}
