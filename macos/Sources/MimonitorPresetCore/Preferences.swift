import Foundation

/// Explicit storage boundary shared by app preferences and the existing preset store.
public protocol PreferencesStore: AnyObject {
    func string(forKey key: String) -> String?
    func data(forKey key: String) -> Data?
    func array(forKey key: String) -> [Any]?
    func bool(forKey key: String) -> Bool
    func integer(forKey key: String) -> Int
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    func register(defaults: [String: Any])
}

extension UserDefaults: PreferencesStore {}

public extension PreferencesStore {
    func string(forKey key: String) -> String? { object(forKey: key) as? String }
    func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    func array(forKey key: String) -> [Any]? { object(forKey: key) as? [Any] }
    func bool(forKey key: String) -> Bool { object(forKey: key) as? Bool ?? false }
    func integer(forKey key: String) -> Int { object(forKey: key) as? Int ?? 0 }
}

/// No preferences domain or files. Also safe for background preset operations.
public final class MemoryPreferences: PreferencesStore {
    private let lock = NSRecursiveLock()
    private var values: [String: Any]
    public init(_ values: [String: Any] = [:]) { self.values = values }
    public func object(forKey key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }; return values[key]
    }
    public func set(_ value: Any?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }; values[key] = value
    }
    public func removeObject(forKey key: String) { set(nil, forKey: key) }
    public func register(defaults: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        for (key, value) in defaults where values[key] == nil { values[key] = value }
    }
}
