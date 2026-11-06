import SwiftUI

/// Holds one pending, undoable action and dismisses it after `window` seconds.
/// Used by every list that offers an "Undo" banner after a destructive change.
@MainActor
@Observable
final class UndoController<Pending> {
    static var window: UInt64 { 6_000_000_000 }

    private(set) var pending: Pending?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    /// Performs `action`, shows the banner for `pending` and schedules its dismissal.
    func schedule(_ pending: Pending, reduceMotion: Bool, action: () -> Void) {
        dismissTask?.cancel()
        action()
        withAnimation(reduceMotion ? nil : .default) {
            self.pending = pending
        }
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.window)
            guard !Task.isCancelled, let self else { return }
            withAnimation(reduceMotion ? nil : .default) {
                self.pending = nil
            }
        }
    }

    /// Hands the pending value to `restore`, then hides the banner.
    func undo(reduceMotion: Bool, restore: (Pending) -> Void) {
        guard let pending else { return }
        dismissTask?.cancel()
        restore(pending)
        withAnimation(reduceMotion ? nil : .default) {
            self.pending = nil
        }
    }

    /// Drops the banner without animation (view disappearing).
    func reset() {
        dismissTask?.cancel()
        pending = nil
    }
}

/// The Undo banner for a controller's pending action, with the shared transition.
struct PendingUndoBanner<Pending>: View {
    let controller: UndoController<Pending>
    let message: (Pending) -> String
    let onUndo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let pending = controller.pending {
            UndoBanner(message: message(pending), onUndo: onUndo)
                .transition(reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity))
        }
    }
}
