import Observation

/// Runs `body` now and again after any observable value it read changes.
/// Stops once a run reads nothing observable, for example after a `[weak self]` capture goes nil.
@MainActor
public func keepObserving(_ body: @escaping @MainActor () -> Void) {
    withObservationTracking(body) {
        Task { @MainActor in keepObserving(body) }
    }
}
