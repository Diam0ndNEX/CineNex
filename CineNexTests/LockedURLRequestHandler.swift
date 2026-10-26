import Foundation

/// Synchronizes the URLProtocol callback installed by a serial network test.
final class LockedURLRequestHandler: @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    private let lock = NSLock()
    private var storedHandler: Handler?

    var handler: Handler? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedHandler = newValue
        }
    }
}
