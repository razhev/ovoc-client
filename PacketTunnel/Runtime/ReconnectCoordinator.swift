import Foundation

/// Pure recovery policy. The provider executes effects on its serial stateQueue.
/// Timer/probe tickets invalidate callbacks already enqueued before cancellation.
struct ReconnectCoordinator {
    enum State: String {
        case idle, starting, online, waitingForNetwork, settling
        case reconnecting, verifying, stoppingAdapter, stopped, failed
    }

    enum Effect: Equatable {
        case reassert(Bool)
        case schedule(ticket: Int, delay: TimeInterval)
        case cancelTimer
        case cancelProbe
        case reconnect(attempt: Int)
        case stopAdapter
        case replaceAdapter(attempt: Int)
        case probe(ticket: Int)
        case ready
        case fail(String)
    }

    private(set) var state: State = .idle
    private(set) var attempts = 0
    private(set) var ticket = 0
    private var path: NetworkPathSnapshot?
    private var changedDuringStart = false
    private var needsNewAdapter = false
    private var awaitingReconnectEvent = false

    mutating func start() {
        self = ReconnectCoordinator()
        state = .starting
    }

    mutating func stop() -> [Effect] {
        state = .stopped
        return invalidate()
    }

    mutating func pathChanged(_ newPath: NetworkPathSnapshot) -> [Effect] {
        let previous = path
        path = newPath
        guard previous != newPath, isActive else { return [] }
        if state == .starting {
            changedDuringStart = changedDuringStart || previous != nil
            return []
        }
        // Finish stopping the old adapter even if the network disappears.
        guard state != .stoppingAdapter else { return [] }
        if !newPath.isAvailable { return waitForNetwork() }
        // The first monitor callback establishes a baseline, not a network switch.
        guard previous != nil || state == .waitingForNetwork else { return [] }
        return settle(delay: 2)
    }

    mutating func connected() -> [Effect] {
        guard isActive, state != .stoppingAdapter else { return [] }
        guard path?.isAvailable != false else { return waitForNetwork() }
        if state == .starting, changedDuringStart {
            changedDuringStart = false
            return settle(delay: 2)
        }
        // A CONNECTED from the previous path must not cancel a pending reconnect.
        guard state == .starting || (state == .reconnecting && !awaitingReconnectEvent) else { return [] }
        if state == .reconnecting {
            state = .verifying
            // Handshake + data-plane verification share the same 30s budget.
            return [.cancelProbe, .probe(ticket: ticket)]
        }
        return verify()
    }

    mutating func reconnecting() -> [Effect] {
        guard isActive else { return [] }
        if state == .reconnecting {
            awaitingReconnectEvent = false
            return [] // OpenVPN's own retries must not extend our deadline.
        }
        guard state == .online || state == .verifying else { return [] }
        guard path?.isAvailable != false else { return waitForNetwork() }
        guard attempts < 3 else { return fail() }
        attempts += 1
        state = .reconnecting
        awaitingReconnectEvent = false
        return invalidate() + [.reassert(true), arm(after: 30)]
    }

    mutating func disconnected() -> [Effect] {
        guard isActive else { return [] }
        guard state != .starting else {
            return fail("Соединение разорвано до установления")
        }
        needsNewAdapter = true
        guard path?.isAvailable != false else { return waitForNetwork() }
        return settle(delay: 2)
    }

    /// Used after wake or outbound traffic without replies. Silence alone is not failure.
    mutating func checkHealth() -> [Effect] {
        guard state == .online else { return [] }
        return verify()
    }

    mutating func probeFinished(ticket received: Int, success: Bool) -> [Effect] {
        guard received == ticket, state == .verifying else { return [] }
        if success {
            state = .online
            attempts = 0
            return invalidate() + [.ready, .reassert(false)]
        }
        return retry()
    }

    mutating func timerFired(ticket received: Int) -> [Effect] {
        guard received == ticket, isActive else { return [] }
        switch state {
        case .settling:
            guard path?.isAvailable != false else { return waitForNetwork() }
            guard attempts < 3 else { return fail() }
            // Last attempt uses a fresh adapter, only after DISCONNECTED.
            if attempts == 2 && !needsNewAdapter {
                state = .stoppingAdapter
                return invalidate() + [.stopAdapter, arm(after: 5)]
            }
            attempts += 1
            state = .reconnecting
            let replace = needsNewAdapter
            needsNewAdapter = false
            awaitingReconnectEvent = !replace
            return invalidate() + [arm(after: 30), replace
                ? .replaceAdapter(attempt: attempts) : .reconnect(attempt: attempts)]
        case .reconnecting, .verifying:
            return retry()
        case .stoppingAdapter:
            return fail("Не удалось остановить транспорт VPN для восстановления соединения")
        default:
            return []
        }
    }

    private var isActive: Bool {
        state != .idle && state != .stopped && state != .failed
    }

    private mutating func verify() -> [Effect] {
        state = .verifying
        let effects = invalidate()
        return effects + [arm(after: 30), .probe(ticket: ticket)]
    }

    private mutating func retry() -> [Effect] {
        guard path?.isAvailable != false else { return waitForNetwork() }
        guard attempts < 3 else { return fail() }
        return settle(delay: attempts == 0 ? 2 : (attempts == 1 ? 5 : 10))
    }

    private mutating func settle(delay: TimeInterval) -> [Effect] {
        state = .settling
        return invalidate() + [.reassert(true), arm(after: delay)]
    }

    private mutating func waitForNetwork() -> [Effect] {
        state = .waitingForNetwork
        // Offline time does not consume the recovery budget of the next path.
        attempts = 0
        return invalidate() + [.reassert(true)]
    }

    private mutating func fail(_ message: String = "Не удалось восстановить VPN после трёх попыток. Проверьте сеть и подключитесь снова.") -> [Effect] {
        state = .failed
        return invalidate() + [.fail(message)]
    }

    private mutating func invalidate() -> [Effect] {
        ticket += 1
        return [.cancelTimer, .cancelProbe]
    }

    private func arm(after delay: TimeInterval) -> Effect {
        .schedule(ticket: ticket, delay: delay)
    }
}
