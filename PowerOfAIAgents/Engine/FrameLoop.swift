import Foundation

/// Drives a simulation at roughly 60 fps on the main actor.
@MainActor
final class FrameLoop {
    /// Longest step a single frame may advance; a suspended app or a hitch never makes the simulation jump ahead.
    static let maxStep = 0.1

    private var task: Task<Void, Never>?

    static func step(elapsed: Duration) -> Double {
        min(max(elapsed.milliseconds / 1000, 0), maxStep)
    }

    /// Calls `tick` with the seconds since the previous frame until it returns false or `stop()` is called.
    func start(_ tick: @escaping @MainActor (Double) -> Bool) {
        stop()
        task = Task { [weak self] in
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                let now = clock.now
                let keepGoing = tick(Self.step(elapsed: last.duration(to: now)))
                last = now
                if !keepGoing {
                    self?.task = nil
                    return
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
