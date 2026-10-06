import Foundation

/// The adapter starts another recursive reader on every tun rebuild, without
/// cancelling its previous read. Keep one OS read and only the newest consumer.
/// A generation belongs to one adapter instance, so a retired reader cannot
/// register again after replacement. Pending OS reads cannot be cancelled.
final class PacketReadPump {
    typealias Completion = ([Data], [NSNumber]) -> Void
    private let lock = NSLock()
    private let read: (@escaping Completion) -> Void
    private var generation = 0
    private var reading = false
    private var consumer: Completion?

    init(read: @escaping (@escaping Completion) -> Void) {
        self.read = read
    }

    func newGeneration() -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        consumer = nil
        return generation
    }

    func isCurrent(_ candidate: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return candidate == generation
    }

    func discardPendingConsumer() {
        lock.lock()
        consumer = nil
        lock.unlock()
    }

    func request(generation candidate: Int, completion: @escaping Completion) {
        lock.lock()
        guard candidate == generation else { lock.unlock(); return }
        consumer = completion
        let shouldRead = !reading
        reading = true
        lock.unlock()
        guard shouldRead else { return }
        read { [weak self] packets, protocols in
            guard let self else { return }
            self.lock.lock()
            self.reading = false
            let callback = self.consumer
            self.consumer = nil
            self.lock.unlock()
            callback?(packets, protocols)
        }
    }
}
