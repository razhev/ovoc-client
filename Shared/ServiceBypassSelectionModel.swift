import Combine

/// The switches commit immediately. Locking begins before the asynchronous save,
/// so dismissing the sheet or starting another edit cannot outrun persistence.
@MainActor
public final class ServiceBypassSelectionModel: ObservableObject {
    @Published public private(set) var selection: Set<BypassService> = []
    @Published public private(set) var isSaving = false
    @Published public private(set) var saveError: Error?

    public init() {}

    public func synchronize(_ policy: ServiceBypassPolicy?) {
        guard !isSaving else { return }
        selection = policy?.services ?? []
    }

    @discardableResult
    public func updateSelection(
        _ services: Set<BypassService>,
        save: @escaping @MainActor (ServiceBypassPolicy) async throws -> Void,
        readSaved: @escaping @MainActor () -> ServiceBypassPolicy?
    ) -> Task<Void, Never>? {
        guard !isSaving, services != selection else { return nil }
        isSaving = true
        saveError = nil
        selection = services
        return Task {
            do { try await save(ServiceBypassPolicy(services: services)) }
            catch { saveError = error }
            // The persistence layer reloads actual system state on both success
            // and failure. Never leave an unsuccessful choice looking saved.
            selection = readSaved()?.services ?? []
            isSaving = false
        }
    }
}
