import SwiftUI

/// The design system, transcribed one-to-one from `docs/tokens.html`.
///
/// Every view reads from here. No component declares a literal color, size,
/// radius, or duration of its own — if something is missing, it gets added as a
/// token rather than inlined at the call site.
///
/// Direction: 1980s portable field recorder. Two decks rather than one theme
/// inverted — light is a cream-and-silver faceplate, dark is matte black with
/// aluminium trim. Both are machines that existed.
enum Tokens {

    // MARK: - Color

    /// Resolves light/dark from the same pair, so callers never branch on scheme.
    private static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }

    enum Surface {
        static let chassis       = pair(0xC9C5BC, 0x1A1B1C)
        static let panel         = pair(0xD8D4CB, 0x26282A)
        static let panelRaised   = pair(0xE2DED5, 0x303336)
        static let recess        = pair(0xB3AFA6, 0x131415)
        static let control       = pair(0xDEDAD1, 0x3A3D40)
        static let controlPressed = pair(0xC2BEB5, 0x232527)
    }

    enum Edge {
        static let seam      = pair(0x8F8B83, 0x0E0F10)
        static let highlight = pair(0xF2EFE8, 0x4D5155)
        static let shadow    = pair(0x9C988F, 0x0D0E0F)
        static let aluminium = pair(0xA8A49B, 0x8E9296)
    }

    enum Text {
        static let primary   = pair(0x2A2825, 0xDCDAD4)
        static let secondary = pair(0x5C5952, 0x9B9891)
        static let label     = pair(0x6B6860, 0x8A8781)
        static let readout   = pair(0x2F2D29, 0xC9C5BB)
    }

    /// The only saturated colors in the system.
    enum Signal {
        static let record    = pair(0xB83228, 0xCF3B2E)
        static let levelSafe = pair(0x4F8F42, 0x6FAE5A)
        static let levelWarn = pair(0xC08420, 0xE0A13A)
        static let levelPeak = pair(0xB83228, 0xCF3B2E)
        /// An unlit record lamp still has a body — it is a bulb, not an absence.
        static let recordDim = pair(0x9A8C89, 0x4A2320)
    }

    // MARK: - Type

    /// Bundled with the app (`ATSApplicationFontsPath`), so a missing system
    /// face can never silently drop the deck back to Helvetica.
    enum FontFamily {
        static let ui = "Archivo"
        static let mono = "Azeret Mono"
    }

    enum Typography {
        // Silkscreen labels: small, uppercase, tightly tracked.
        static let labelMicro  = Font.custom(FontFamily.ui, fixedSize: 9).weight(.semibold)
        static let label       = Font.custom(FontFamily.ui, fixedSize: 10).weight(.semibold)
        static let labelLarge  = Font.custom(FontFamily.ui, fixedSize: 11).weight(.bold)

        static let bodySmall   = Font.custom(FontFamily.ui, fixedSize: 12)
        static let body        = Font.custom(FontFamily.ui, fixedSize: 13)
        static let bodyLarge   = Font.custom(FontFamily.ui, fixedSize: 15)
        static let title       = Font.custom(FontFamily.ui, fixedSize: 18).weight(.semibold)
        static let display     = Font.custom(FontFamily.ui, fixedSize: 24).weight(.bold)

        // Anything that counts.
        static let readoutSmall = Font.custom(FontFamily.mono, fixedSize: 12)
        static let readout      = Font.custom(FontFamily.mono, fixedSize: 20).weight(.medium)
        static let readoutLarge = Font.custom(FontFamily.mono, fixedSize: 32).weight(.semibold)

        /// Tracking for uppercase silkscreen labels, by size.
        enum Tracking {
            static let micro: CGFloat = 1.35   // 0.15em at 9pt
            static let label: CGFloat = 1.40   // 0.14em at 10pt
            static let large: CGFloat = 1.32   // 0.12em at 11pt
        }
    }

    // MARK: - Space — 4pt grid

    enum Space {
        static let hair: CGFloat = 2
        static let tight: CGFloat = 4
        static let snug: CGFloat = 8
        static let base: CGFloat = 12
        static let loose: CGFloat = 16
        static let section: CGFloat = 24
        static let panel: CGFloat = 32
        static let deck: CGFloat = 48
    }

    // MARK: - Radius — equipment has milled edges, nothing exceeds 5

    enum Radius {
        static let none: CGFloat = 0
        static let control: CGFloat = 2
        static let panel: CGFloat = 3
        static let chassis: CGFloat = 5
    }

    enum Border {
        static let hairline: CGFloat = 1
        static let bezel: CGFloat = 2
    }

    // MARK: - Depth
    //
    // A control reads as pressed because its bevel inverts, not because the
    // fill changed tint. Hence highlight/shadow pairs rather than drop shadows.

    enum Depth {
        struct Bevel {
            var topHighlight: Color
            var bottomShadow: Color
            var castOpacity: Double
            var castRadius: CGFloat
            var castY: CGFloat
        }

        static let raised = Bevel(
            topHighlight: Edge.highlight, bottomShadow: Edge.shadow,
            castOpacity: 0.28, castRadius: 2, castY: 1
        )
        static let pressed = Bevel(
            topHighlight: Edge.shadow, bottomShadow: Edge.highlight,
            castOpacity: 0.0, castRadius: 0, castY: 0
        )
        static let panelCast = Bevel(
            topHighlight: Edge.highlight, bottomShadow: Edge.seam,
            castOpacity: 0.22, castRadius: 2, castY: 1
        )
    }

    // MARK: - Motion

    enum Motion {
        /// A key travels and stops. It does not ease elegantly into place.
        static let keyTravel: Duration = .milliseconds(60)
        static let state: Duration = .milliseconds(120)

        /// VU standard: 99% of a steady tone in 300ms, symmetric fall.
        static let needleRise: Double = 0.300
        static let needleFall: Double = 0.300
        static let peakHold: Double = 1.200

        static let ease = SwiftUI.Animation.timingCurve(0.2, 0, 0, 1)

        static func keyTravelAnimation() -> SwiftUI.Animation {
            .timingCurve(0.2, 0, 0, 1, duration: 0.060)
        }
        static func stateAnimation() -> SwiftUI.Animation {
            .timingCurve(0.2, 0, 0, 1, duration: 0.120)
        }
    }
}

extension NSColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
