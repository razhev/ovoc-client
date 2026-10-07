import Foundation

/// Pure recovery policy. The provider executes effects on its serial stateQueue.
/// Timer/probe tickets invalidate callbacks already enqueued before cancellation.
struct ReconnectCoordinator {
    enum State: String {
        case idle, starting, online, unverified, waitingForNetwork, settling
        case reconnecting, verifying, probeBackoff, healthCooldown, stoppingAdapter, stopped, failed
    }

    enum Effect: Equatable {
        case reassert(Bool)
        case schedule(ticket: Int, delay: TimeInterval)
        case cancelTimer
        case cancelProbe
        case reconnect(attempt: Int)
        case stopAdapter
        case replaceAdapter(attempt: Int)
        case activateTunnel
        case probe(ticket: Int)
        case ready
        case fail(String)
    }

    private(set) var state: State = .idle
    private(set) var attempts = 0
    private(set) var ticket = 0
    private var path: NetworkPathSnapshot?
    private var workingPath: NetworkPathSnapshot?
    private var pathChangedDuringAttempt = false
    private var checkingRestoredPath = false
    private var advisoryVerification = false
    private var failedProbes = 0
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
        if state == .starting { return [] }
        // A monitor callback must not cancel an in-flight reconnect's deadline
        // or enqueue another reconnect before the core has answered the first.
        if state == .reconnecting || (state == .verifying && !advisoryVerification) {
            pathChangedDuringAttempt = true
            return []
        }
        guard state != .stoppingAdapter else { return [] }
        if !newPath.isAvailable { return waitForNetwork() }
        guard previous != nil || state == .waitingForNetwork else {
            workingPath = newPath
            return []
        }
        if state == .unverified { attempts = 0 }
        checkingRestoredPath = !needsNewAdapter && newPath == workingPath
        return settle(delay: 3, reassert: !checkingRestoredPath)
    }

    mutating func connected() -> [Effect] {
        guard isActive, state != .stoppingAdapter else { return [] }
        guard path?.isAvailable != false else { return waitForNetwork() }
        // A CONNECTED from the previous path must not cancel a pending reconnect.
        guard state == .starting || (state == .reconnecting && !awaitingReconnectEvent) else { return [] }
        if state == .reconnecting {
            state = .verifying
            advisoryVerification = false
            pathChangedDuringAttempt = false
            // Handshake + data-plane verification share the same 30s budget.
            return [.activateTunnel, .reassert(false), .cancelProbe, .probe(ticket: ticket)]
        }
        // iOS must finish starting (or reasserting) before a connection scoped
        // to the virtual interface can reliably exchange traffic. Do not make
        // activation depend on a probe that itself needs an activated tunnel.
        return [.activateTunnel, .reassert(false)] + verify(advisory: true)
    }

    mutating func reconnecting() -> [Effect] {
        guard isActive else { return [] }
        if state == .reconnecting {
            awaitingReconnectEvent = false
            return [] // OpenVPN's own retries must not extend our deadline.
        }
        guard state == .online || state == .unverified || state == .verifying || state == .probeBackoff || state == .healthCooldown else { return [] }
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
        checkingRestoredPath = false
        guard path?.isAvailable != false else { return waitForNetwork() }
        return settle(delay: 2)
    }

    /// Used after wake or outbound traffic without replies. Silence alone is not failure.
    mutating func checkHealth() -> [Effect] {
        guard state == .online else { return [] }
        failedProbes = 0
        return verify(advisory: true)
    }

    mutating func probeFinished(ticket received: Int, success: Bool) -> [Effect] {
        probeFinished(ticket: received, result: success ? .success : .noReply)
    }

    mutating func probeFinished(ticket received: Int, result: TunnelProbeResult) -> [Effect] {
        guard received == ticket, state == .verifying || state == .probeBackoff || (state == .unverified && result == .success) else { return [] }
        // A reply issued before a path change cannot validate the new path.
        guard advisoryVerification || !pathChangedDuringAttempt else { return [] }
        if result == .success {
            state = .online
            workingPath = path
            attempts = 0
            failedProbes = 0
            return invalidate() + [.ready, .reassert(false)]
        }
        guard advisoryVerification else {
            // Local inability to send a scoped probe says nothing about the VPN.
            // Keep the original recovery deadline and accept actual inbound traffic.
            return result == .inconclusive ? [] : retry()
        }
        if result == .inconclusive {
            state = .healthCooldown
            failedProbes = 0
            return invalidate() + [.reassert(false), arm(after: 60)]
        }
        failedProbes += 1
        if failedProbes < 3 {
            state = .probeBackoff
            return invalidate() + [arm(after: 15)]
        }
        return retry()
    }

    /// A profile may intentionally bypass all its DNS servers. No eligible
    /// target is not evidence of transport failure; keep monitoring core/path.
    mutating func probeUnavailable(ticket received: Int) -> [Effect] {
        guard received == ticket, state == .verifying else { return [] }
        state = .unverified
        workingPath = path
        return invalidate() + [.reassert(false)]
    }

    mutating func timerFired(ticket received: Int) -> [Effect] {
        guard received == ticket, isActive else { return [] }
        switch state {
        case .healthCooldown:
            state = .online
            return invalidate()
        case .probeBackoff:
            return verify(advisory: true)
        case .settling:
            if checkingRestoredPath {
                checkingRestoredPath = false
                failedProbes = 0
                return [.reassert(false)] + verify(advisory: true)
            }
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
            pathChangedDuringAttempt = false
            return invalidate() + [arm(after: 30), replace
                ? .replaceAdapter(attempt: attempts) : .reconnect(attempt: attempts)]
        case .reconnecting:
            // Never stack commands behind a reconnect that the core has not
            // acknowledged. Stop it before creating a replacement.
            if awaitingReconnectEvent {
                state = .stoppingAdapter
                return invalidate() + [.stopAdapter, arm(after: 5)]
            }
            return retry()
        case .verifying:
            if advisoryVerification {
                return probeFinished(ticket: ticket, result: .inconclusive)
            }
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

    private mutating func verify(advisory: Bool) -> [Effect] {
        advisoryVerification = advisory
        state = .verifying
        let effects = invalidate()
        return effects + [arm(after: 30), .probe(ticket: ticket)]
    }

    private mutating func retry() -> [Effect] {
        checkingRestoredPath = false
        guard path?.isAvailable != false else { return waitForNetwork() }
        guard attempts < 3 else { return fail() }
        return settle(delay: attempts == 0 ? 2 : (attempts == 1 ? 5 : 10))
    }

    private mutating func settle(delay: TimeInterval, reassert: Bool = true) -> [Effect] {
        state = .settling
        return invalidate() + [.reassert(reassert), arm(after: delay)]
    }

    private mutating func waitForNetwork() -> [Effect] {
        state = .waitingForNetwork
        // Offline time does not consume the recovery budget of the next path.
        attempts = 0
        checkingRestoredPath = false
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
