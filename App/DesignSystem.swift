import SwiftUI

/// Design tokens lifted from the Claude DESIGN.md spec
/// (https://getdesign.md/claude/design-md). The brand is anchored on a tinted
/// cream canvas with serif display headlines, warm coral CTAs, and dark-navy
/// product surfaces. We deliberately stay in light-mode aesthetics — the
/// spec is light-only and inverts only on individual dark surfaces, never on
/// the whole shell.
enum DS {
    // MARK: - Colors
    enum Color {
        // Brand & accent
        static let primary       = SwiftUI.Color(hex: 0xCC785C)
        static let primaryActive = SwiftUI.Color(hex: 0xA9583E)
        static let primaryDisabled = SwiftUI.Color(hex: 0xE6DFD8)
        static let accentTeal    = SwiftUI.Color(hex: 0x5DB8A6)
        static let accentAmber   = SwiftUI.Color(hex: 0xE8A55A)
        // Text
        static let ink           = SwiftUI.Color(hex: 0x141413)
        static let bodyStrong    = SwiftUI.Color(hex: 0x252523)
        static let body          = SwiftUI.Color(hex: 0x3D3D3A)
        static let muted         = SwiftUI.Color(hex: 0x6C6A64)
        static let mutedSoft     = SwiftUI.Color(hex: 0x8E8B82)
        static let onPrimary     = SwiftUI.Color.white
        static let onDark        = SwiftUI.Color(hex: 0xFAF9F5)
        static let onDarkSoft    = SwiftUI.Color(hex: 0xA09D96)
        // Surfaces
        static let canvas        = SwiftUI.Color(hex: 0xFAF9F5)
        static let surfaceSoft   = SwiftUI.Color(hex: 0xF5F0E8)
        static let surfaceCard   = SwiftUI.Color(hex: 0xEFE9DE)
        static let surfaceCreamStrong = SwiftUI.Color(hex: 0xE8E0D2)
        static let surfaceDark   = SwiftUI.Color(hex: 0x181715)
        static let surfaceDarkElevated = SwiftUI.Color(hex: 0x252320)
        static let surfaceDarkSoft = SwiftUI.Color(hex: 0x1F1E1B)
        // Hairlines
        static let hairline      = SwiftUI.Color(hex: 0xE6DFD8)
        static let hairlineSoft  = SwiftUI.Color(hex: 0xEBE6DF)
        // Semantic
        static let success       = SwiftUI.Color(hex: 0x5DB872)
        static let warning       = SwiftUI.Color(hex: 0xD4A017)
        static let error         = SwiftUI.Color(hex: 0xC64545)
    }

    // MARK: - Spacing (4px base)
    enum Space {
        static let xxs: CGFloat = 4
        static let xs:  CGFloat = 8
        static let sm:  CGFloat = 12
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
        static let section: CGFloat = 96
    }

    // MARK: - Radius
    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let pill: CGFloat = 9999
    }

    // MARK: - Typography
    /// Copernicus / Tiempos Headline substitute → SF "New York" via .serif design.
    /// Negative letter-spacing is non-negotiable per the spec.
    enum Typo {
        // Display: serif, weight 400, negative tracking
        static func displayXL() -> Font { .system(size: 56, weight: .regular, design: .serif) }
        static func displayLG() -> Font { .system(size: 44, weight: .regular, design: .serif) }
        static func displayMD() -> Font { .system(size: 32, weight: .regular, design: .serif) }
        static func displaySM() -> Font { .system(size: 26, weight: .regular, design: .serif) }
        // Title: humanist sans, weight 500
        static func titleLG() -> Font { .system(size: 22, weight: .medium, design: .default) }
        static func titleMD() -> Font { .system(size: 18, weight: .medium, design: .default) }
        static func titleSM() -> Font { .system(size: 16, weight: .medium, design: .default) }
        // Body / caption
        static func bodyMD() -> Font { .system(size: 16, weight: .regular, design: .default) }
        static func bodySM() -> Font { .system(size: 14, weight: .regular, design: .default) }
        static func caption() -> Font { .system(size: 13, weight: .medium, design: .default) }
        static func captionUpper() -> Font { .system(size: 12, weight: .medium, design: .default) }
        static func code() -> Font { .system(size: 14, weight: .regular, design: .monospaced) }
        static func button() -> Font { .system(size: 15, weight: .medium, design: .default) }

        // Tracking helpers — apply with .tracking(...).
        static let displayTrackingTight: CGFloat = -1.0
        static let captionUpperTracking: CGFloat = 1.5
    }
}

// MARK: - Hex initializer
extension SwiftUI.Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >>  8) & 0xFF) / 255
        let b = Double( hex        & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - Reusable view modifiers / styles

/// Coral primary CTA — the signature button. Used for "开始游戏", "提交",
/// "下一局", "再来一局".
struct CoralPrimaryButtonStyle: ButtonStyle {
    var isFullWidth: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typo.button())
            .foregroundStyle(DS.Color.onPrimary)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(configuration.isPressed ? DS.Color.primaryActive : DS.Color.primary)
            )
            .opacity(configuration.isPressed ? 0.95 : 1)
    }
}

/// Cream secondary button with a 1px hairline border. Used for "清空".
struct CreamSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typo.button())
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.Color.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Color.hairline, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Coral inline text link.
struct CoralTextLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typo.button())
            .foregroundStyle(DS.Color.primary)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Cream surface card with rounded.lg radius and hairline border. Used as
/// the container for the QuickDraw playback area and the player's PencilKit
/// canvas.
struct CreamCardModifier: ViewModifier {
    var padding: CGFloat = DS.Space.md
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(DS.Color.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(DS.Color.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func creamCard(padding: CGFloat = DS.Space.md) -> some View {
        modifier(CreamCardModifier(padding: padding))
    }
}

/// Coral pill badge — used for the round counter "第 X/6 局".
struct CoralPillModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DS.Typo.captionUpper())
            .tracking(DS.Typo.captionUpperTracking)
            .foregroundStyle(DS.Color.onPrimary)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, 4)
            .background(Capsule().fill(DS.Color.primary))
    }
}

/// Cream-card pill — for the entitlement HUD.
struct CreamPillModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DS.Typo.caption())
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, 4)
            .background(Capsule().fill(DS.Color.surfaceCard))
    }
}

extension View {
    func coralPill() -> some View { modifier(CoralPillModifier()) }
    func creamPill() -> some View { modifier(CreamPillModifier()) }
}
