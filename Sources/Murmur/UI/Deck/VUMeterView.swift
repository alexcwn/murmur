import SwiftUI

/// A moving-coil VU meter.
///
/// The needle is not a level readout with a spring animation bolted on — it
/// follows the actual VU ballistic: 99% of a steady tone in 300 ms, symmetric
/// fall. That weighting is why an analogue meter reads as an instrument and a
/// bar graph tracking instantaneous amplitude does not.
struct VUMeterView: View {
    /// Target level, 0…1.
    var level: Double
    /// While false the needle rests and the timeline stops.
    var isActive: Bool

    @State private var ballistics = Ballistics()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Classic VU face. Value is the fraction along the arc, not dB linear.
    private static let ticks: [(v: Double, label: String, red: Bool)] = [
        (0.00, "-20", false), (0.25, "-10", false), (0.37, "-7", false),
        (0.46, "-5", false), (0.56, "-3", false), (0.66, "-1", false),
        (0.72, "0", true), (0.80, "+1", true), (1.00, "+3", true),
    ]
    private static let redZoneStart = 0.72

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isActive)) { timeline in
            Canvas { context, size in
                ballistics.advance(
                    to: isActive ? level : 0,
                    at: timeline.date,
                    instant: reduceMotion
                )
                draw(context: context, size: size)
            }
        }
        .background(Tokens.Surface.recess)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.control)
                .strokeBorder(Tokens.Edge.seam, lineWidth: Tokens.Border.hairline)
        }
        .accessibilityElement()
        .accessibilityLabel("Input level")
        .accessibilityValue(isActive ? "\(Int(level * 100)) percent" : "Idle")
    }

    // MARK: - Drawing

    private func geometry(_ size: CGSize) -> (pivot: CGPoint, radius: CGFloat) {
        let pivot = CGPoint(x: size.width / 2, y: size.height * 0.88)
        let radius = min(size.width * 0.40, size.height * 0.74)
        return (pivot, radius)
    }

    private func point(_ v: Double, radius: CGFloat, in size: CGSize) -> CGPoint {
        let (pivot, _) = geometry(size)
        let angle = (-50 + 100 * v) * .pi / 180
        return CGPoint(
            x: pivot.x + radius * sin(angle),
            y: pivot.y - radius * cos(angle)
        )
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let (pivot, r) = geometry(size)
        guard r > 8 else { return }

        // Scale arc, then the red zone drawn over it more heavily.
        var arc = Path()
        arc.addArc(center: pivot, radius: r,
                   startAngle: .degrees(-140), endAngle: .degrees(-40),
                   clockwise: false)
        context.stroke(arc, with: .color(Tokens.Text.secondary), lineWidth: 1.2)

        var red = Path()
        red.addArc(center: pivot, radius: r,
                   startAngle: .degrees(-140 + 100 * Self.redZoneStart), endAngle: .degrees(-40),
                   clockwise: false)
        context.stroke(red, with: .color(Tokens.Signal.levelPeak), lineWidth: 2.2)

        // Ticks and their numbers.
        for tick in Self.ticks {
            var path = Path()
            path.move(to: point(tick.v, radius: r * 0.89, in: size))
            path.addLine(to: point(tick.v, radius: r, in: size))
            context.stroke(
                path,
                with: .color(tick.red ? Tokens.Signal.levelPeak : Tokens.Text.secondary),
                lineWidth: tick.red ? 1.2 : 1
            )

            let text = Text(tick.label)
                .font(.custom(Tokens.FontFamily.mono, fixedSize: max(6, r * 0.085)))
                .foregroundStyle(tick.red ? Tokens.Signal.levelPeak : Tokens.Text.secondary)
            context.draw(text, at: point(tick.v, radius: r * 0.74, in: size), anchor: .center)
        }

        context.draw(
            Text("VU")
                .font(.custom(Tokens.FontFamily.ui, fixedSize: max(6, r * 0.09)).weight(.bold))
                .tracking(1.6)
                .foregroundStyle(Tokens.Text.label),
            at: CGPoint(x: pivot.x, y: pivot.y - r * 0.22),
            anchor: .center
        )

        // Peak marker, held then released.
        var peak = Path()
        peak.move(to: point(ballistics.peak, radius: r * 0.98, in: size))
        peak.addLine(to: point(ballistics.peak, radius: r * 1.08, in: size))
        context.stroke(peak, with: .color(Tokens.Signal.levelPeak), lineWidth: 1.6)

        // Needle and hub.
        var needle = Path()
        needle.move(to: pivot)
        needle.addLine(to: point(ballistics.shown, radius: r * 0.92, in: size))
        context.stroke(
            needle,
            with: .color(Tokens.Text.primary),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
        )

        let hub = CGRect(x: pivot.x - 4, y: pivot.y - 4, width: 8, height: 8)
        context.fill(Path(ellipseIn: hub), with: .color(Tokens.Edge.aluminium))
        context.stroke(Path(ellipseIn: hub), with: .color(Tokens.Edge.seam), lineWidth: 1)
    }
}

/// Needle physics, kept outside the SwiftUI graph so advancing it during a draw
/// pass cannot trigger an invalidation loop.
final class Ballistics {
    private(set) var shown: Double = 0
    private(set) var peak: Double = 0

    private var lastTick: Date?
    private var peakSetAt: Date = .distantPast

    /// Time constant that reaches 99% of a step in exactly `needleRise`.
    private static let tau = Tokens.Motion.needleRise / log(100)

    func advance(to target: Double, at now: Date, instant: Bool) {
        defer { lastTick = now }

        if instant {
            shown = target
            peak = max(target, peak)
            if peak <= target { peakSetAt = now }
            return
        }

        let dt = min(0.064, now.timeIntervalSince(lastTick ?? now))
        guard dt > 0 else { return }

        shown += (target - shown) * (1 - exp(-dt / Self.tau))

        if shown >= peak {
            peak = shown
            peakSetAt = now
        } else if now.timeIntervalSince(peakSetAt) > Tokens.Motion.peakHold {
            peak += (shown - peak) * (1 - exp(-dt / 0.26))
        }
    }
}
