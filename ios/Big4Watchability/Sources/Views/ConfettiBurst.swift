import SwiftUI
import UIKit

// Swift mirror of ConfettiBurst.kt - one-shot particle burst drawn from a
// tile's tier-badge corner when an Instant Classic result is first revealed.
// Not a general-purpose confetti system, just enough for this one easter
// egg: [particleCount] rectangles fired outward from a fixed origin, eased
// out with a light downward drift (gravity), fading to transparent as they
// travel. Calls [onFinished] once the animation completes so the caller can
// stop compositing this overlay.
private let particleCount = 40
private let burstDuration: Double = 2.7
private let confettiColors: [Color] = [.red, .orange, .yellow]

private struct ConfettiParticle {
    let angleDegrees: Double
    let distance: Double
    let color: Color
    let size: Double
    let rotationDegrees: Double
}

struct ConfettiBurst: View {
    var onFinished: () -> Void = {}

    @State private var particles: [ConfettiParticle] = (0..<particleCount).map { _ in
        ConfettiParticle(
            angleDegrees: Double.random(in: 0..<360),
            distance: 280 + Double.random(in: 0..<440),
            color: confettiColors.randomElement() ?? .orange,
            size: 8 + Double.random(in: 0..<8),
            rotationDegrees: (Double.random(in: 0..<1) - 0.5) * 900
        )
    }
    @State private var startDate = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let elapsed = timeline.date.timeIntervalSince(startDate)
                let t = min(elapsed / burstDuration, 1.0)
                let eased = 1 - (1 - t) * (1 - t)
                let alpha = max(0, min(1, 1 - t))
                let originX = 60.0
                let originY = 40.0

                for particle in particles {
                    let radians = particle.angleDegrees * .pi / 180
                    let dist = particle.distance * eased
                    let x = originX + dist * cos(radians)
                    let y = originY + dist * sin(radians) + t * t * 200

                    context.drawLayer { layer in
                        layer.translateBy(x: x, y: y)
                        layer.rotate(by: .degrees(particle.rotationDegrees * t))
                        let rect = CGRect(x: -particle.size / 2, y: -particle.size * 0.8, width: particle.size, height: particle.size * 1.6)
                        layer.fill(Path(rect), with: .color(particle.color.opacity(alpha)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { startDate = Date() }
        .task {
            try? await Task.sleep(nanoseconds: UInt64(burstDuration * 1_000_000_000))
            onFinished()
        }
    }
}

/// Fires once per game.id for the life of the process - a game that's
/// already Instant Classic every time its tile re-renders (scrolling it in
/// and out of view, switching tabs and back) only gets the burst the first
/// time, not on every recomposition. Marked even when confettiEnabled is
/// off, so turning the setting back on later doesn't retroactively fire it
/// for games that already finished while it was disabled. Main-actor-only
/// (all call sites are SwiftUI view bodies), so a plain Set is safe here.
@MainActor
enum InstantClassicCelebrationTracker {
    private static var celebrated = Set<String>()

    /// Returns true the first time this id is seen, false every time after.
    static func markIfFirstTime(_ id: String) -> Bool {
        if celebrated.contains(id) { return false }
        celebrated.insert(id)
        return true
    }
}

@MainActor
func fireInstantClassicHaptic() {
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
}
