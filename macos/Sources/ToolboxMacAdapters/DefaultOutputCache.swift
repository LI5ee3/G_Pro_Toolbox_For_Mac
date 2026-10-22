import Foundation
import CoreAudio
import ToolboxDomain
import ToolboxApplication

/// MainActor owns the cache and lifecycle. CoreAudio reads run only on a private serial queue;
/// event-tap callbacks read a recent immutable snapshot and never enumerate CoreAudio devices.
@MainActor package final class DefaultOutputCache {
    private let queue = DispatchQueue(label: "com.mimonitor.toolbox.audio-output", qos: .utility)
    private let read: @Sendable () -> AudioOutputSnapshot?
    private let observe: (@escaping @MainActor () -> Void) -> RuntimeCancellation
    private let schedule: (@escaping @MainActor () -> Void) -> RuntimeCancellation
    private let now: () -> TimeInterval
    private var observer: RuntimeCancellation?
    private var reconciliation: RuntimeCancellation?
    private var active = false, generation = 0, request = 0
    private var value: AudioOutputSnapshot?
    private var updatedAt: TimeInterval = 0
    package init(read: @escaping @Sendable () -> AudioOutputSnapshot?,
                 observe: @escaping (@escaping @MainActor () -> Void) -> RuntimeCancellation,
                 schedule: @escaping (@escaping @MainActor () -> Void) -> RuntimeCancellation,
                 now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.read = read; self.observe = observe; self.schedule = schedule; self.now = now
    }
    package static func live() -> DefaultOutputCache {
        DefaultOutputCache(read: { CoreAudioOutputReader.snapshot() }, observe: { changed in
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { _, _ in DispatchQueue.main.async { changed() } }
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
            return RuntimeCancellation {
                if status == noErr { _ = AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) }
            }
        }, schedule: { action in
            let timer = Timer(timeInterval: 5, repeats: true) { _ in MainActor.assumeIsolated { action() } }
            RunLoop.main.add(timer, forMode: .common)
            return RuntimeCancellation { timer.invalidate() }
        })
    }
    package func start() {
        guard !active else { return }
        active = true; generation &+= 1
        let epoch = generation
        observer = observe { [weak self] in
            guard let self, self.active, self.generation == epoch else { return }
            self.refresh()
        }
        reconciliation = schedule { [weak self] in
            guard let self, self.active, self.generation == epoch else { return }
            self.refresh(invalidate: false)
        }
        refresh()
    }
    package func refresh(invalidate: Bool = true) {
        guard active else { return }
        if invalidate { value = nil }
        request &+= 1
        let revision = request, epoch = generation
        queue.async { [read, weak self] in
            let result = read()
            DispatchQueue.main.async {
                guard let self, self.active, self.generation == epoch, self.request == revision else { return }
                self.value = result; self.updatedAt = self.now()
            }
        }
    }
    package func snapshot() -> AudioOutputSnapshot? {
        guard active, now() - updatedAt <= 10 else { return nil }
        return value
    }
    package func stop() {
        active = false; generation &+= 1; value = nil
        observer?.invalidate(); observer = nil
        reconciliation?.invalidate(); reconciliation = nil
    }
    /// Test barrier; no device query or main-thread blocking.
    package func waitForRefresh() async {
        await withCheckedContinuation { continuation in
            queue.async { DispatchQueue.main.async { continuation.resume() } }
        }
    }
    isolated deinit {
        observer?.invalidate(); reconciliation?.invalidate()
    }
}
