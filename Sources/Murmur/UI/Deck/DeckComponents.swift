import SwiftUI

// The physical vocabulary of the deck. Every control in the app is built from
// these, and each one reads exclusively from `Tokens`.

// MARK: - Silkscreen

/// Small, uppercase, tightly tracked — the labels printed onto a faceplate.
struct Silkscreen: View {
    enum Size { case micro, normal, large }

    var text: String
    var size: Size = .normal
    var color: Color = Tokens.Text.label

    var body: some View {
        Text(text.uppercased())
            .font(font)
            .tracking(tracking)
            .foregroundStyle(color)
    }

    private var font: Font {
        switch size {
        case .micro: Tokens.Typography.labelMicro
        case .normal: Tokens.Typography.label
        case .large: Tokens.Typography.labelLarge
        }
    }

    private var tracking: CGFloat {
        switch size {
        case .micro: Tokens.Typography.Tracking.micro
        case .normal: Tokens.Typography.Tracking.label
        case .large: Tokens.Typography.Tracking.large
        }
    }
}

// MARK: - Surfaces

/// Fine vertical striation. A gradient sheen would read as skeuomorphic
/// pastiche; real brushed metal is directional texture, not a highlight.
struct BrushedAluminium: View {
    var body: some View {
        Canvas { context, size in
            var light = Path()
            var dark = Path()
            var x: CGFloat = 0
            while x < size.width {
                light.addRect(CGRect(x: x, y: 0, width: 1, height: size.height))
                dark.addRect(CGRect(x: x + 1, y: 0, width: 1, height: size.height))
                x += 2
            }
            context.fill(light, with: .color(.white.opacity(0.05)))
            context.fill(dark, with: .color(.black.opacity(0.035)))
        }
        .allowsHitTesting(false)
    }
}

/// A raised faceplate: brushed, hard-edged, with a lit top border.
struct Faceplate<Content: View>: View {
    var padding: CGFloat = Tokens.Space.base
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                Tokens.Surface.panel
                BrushedAluminium()
            }
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.panel)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Tokens.Edge.highlight, Tokens.Edge.seam],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: Tokens.Border.hairline
                    )
            }
            .shadow(color: .black.opacity(Tokens.Depth.panelCast.castOpacity),
                    radius: Tokens.Depth.panelCast.castRadius,
                    y: Tokens.Depth.panelCast.castY)
    }
}

/// An inset well — where meters, readouts and lists sit.
struct Well<Content: View>: View {
    var padding: CGFloat = Tokens.Space.snug
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Tokens.Surface.recess)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.control)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Tokens.Edge.seam, Tokens.Edge.highlight],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: Tokens.Border.hairline
                    )
            }
    }
}

// MARK: - Controls

/// A key that travels. Pressed state inverts the bevel rather than tinting the
/// fill, which is what makes it read as a physical control.
struct DeckButton: View {
    var title: String
    var isLatched: Bool = false
    var tint: Color = Tokens.Text.primary
    /// Lights while latched. Real transport keys tell you they are engaged with
    /// a lamp, not by a shade of grey — without it, latched and idle look alike.
    var indicator: Color? = nil
    var isEnabled: Bool = true
    var action: () -> Void

    @State private var isDown = false

    private var pressed: Bool { isDown || isLatched }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.tight) {
                if let indicator {
                    Circle()
                        .fill(isLatched ? indicator : Tokens.Signal.recordDim)
                        .frame(width: 5, height: 5)
                        .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.5))
                        .shadow(color: isLatched ? indicator.opacity(0.8) : .clear, radius: 3)
                }
                Silkscreen(text: title, color: isEnabled ? tint : Tokens.Text.secondary)
            }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Tokens.Space.snug)
                .padding(.horizontal, Tokens.Space.base)
                .background(pressed ? Tokens.Surface.controlPressed : Tokens.Surface.control)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
                .overlay {
                    RoundedRectangle(cornerRadius: Tokens.Radius.control)
                        .strokeBorder(
                            LinearGradient(
                                colors: pressed
                                    ? [Tokens.Edge.shadow, Tokens.Edge.highlight]
                                    : [Tokens.Edge.highlight, Tokens.Edge.shadow],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: Tokens.Border.hairline
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Tokens.Radius.control)
                        .strokeBorder(Tokens.Edge.seam.opacity(0.55),
                                      lineWidth: Tokens.Border.hairline)
                }
                // Light falling into a depression: darkest at the top edge.
                .overlay {
                    if pressed {
                        LinearGradient(
                            colors: [.black.opacity(0.16), .clear],
                            startPoint: .top, endPoint: .center
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
                        .allowsHitTesting(false)
                    }
                }
                .shadow(color: .black.opacity(pressed ? 0 : Tokens.Depth.raised.castOpacity),
                        radius: pressed ? 0 : Tokens.Depth.raised.castRadius,
                        y: pressed ? 0 : Tokens.Depth.raised.castY)
                .opacity(isEnabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(Tokens.Motion.keyTravelAnimation(), value: pressed)
        .onLongPressGesture(minimumDuration: 0, pressing: { isDown = $0 }, perform: {})
    }
}

/// The record light. Unlit it still has a body — it is a bulb, not an absence.
struct RecordLamp: View {
    var isLit: Bool

    var body: some View {
        Circle()
            .fill(isLit ? Tokens.Signal.record : Tokens.Signal.recordDim)
            .frame(width: 9, height: 9)
            .overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 1))
            .shadow(color: isLit ? Tokens.Signal.record.opacity(0.85) : .clear, radius: 4)
            .animation(Tokens.Motion.stateAnimation(), value: isLit)
            .accessibilityLabel(isLit ? "Recording" : "Not recording")
    }
}

/// A counter readout, in the monospaced face with tabular figures.
struct Readout: View {
    enum Size { case small, normal, large }

    var text: String
    var size: Size = .normal

    var body: some View {
        Text(text)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(Tokens.Text.readout)
    }

    private var font: Font {
        switch size {
        case .small: Tokens.Typography.readoutSmall
        case .normal: Tokens.Typography.readout
        case .large: Tokens.Typography.readoutLarge
        }
    }
}

/// A hairline seam between panels.
struct Seam: View {
    var body: some View {
        Rectangle()
            .fill(Tokens.Edge.seam)
            .frame(height: Tokens.Border.hairline)
    }
}
