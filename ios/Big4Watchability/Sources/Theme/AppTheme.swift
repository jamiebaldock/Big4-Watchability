import SwiftUI

// Swift mirror of ui/theme/Color.kt - exact hex values from
// docs/nba-app-design-prompt.md, kept in sync with that file. Read via
// @Environment(\.appTheme), set once at RootView based on the persisted
// lightTheme setting - same idea as Color.kt's LocalIsLightTheme, just
// SwiftUI's Environment instead of a CompositionLocal.
struct AppTheme {
    let backgroundBase: Color
    let surfaceCard: Color
    let surfaceCardElevated: Color
    let textPrimary: Color
    let textSecondary: Color
    let textMuted: Color

    static let dark = AppTheme(
        backgroundBase: Color(hex: 0x101418),
        surfaceCard: Color(hex: 0x1A2027),
        surfaceCardElevated: Color(hex: 0x222A33),
        textPrimary: Color(hex: 0xE8EAED),
        textSecondary: Color(hex: 0x8A94A0),
        textMuted: Color(hex: 0x7A8592)
    )

    // Not just an inverted dark scheme - see Color.kt's own note: chosen to
    // keep the same relative contrast steps the dark palette already has.
    static let light = AppTheme(
        backgroundBase: Color(hex: 0xF4F5F7),
        surfaceCard: Color(hex: 0xFFFFFF),
        surfaceCardElevated: Color(hex: 0xEBEDF1),
        textPrimary: Color(hex: 0x14181D),
        textSecondary: Color(hex: 0x4B5563),
        textMuted: Color(hex: 0x6B7280)
    )
}

// Status/tier accents - identical across both themes (Color.kt keeps these
// the same for both light and dark too).
enum AppColors {
    static let liveRed = Color(hex: 0xE8452C)
    static let tierInstantClassic = Color(hex: 0xFFB020)
    static let tierWorthYourTime = Color(hex: 0x33C2A8)
    static let tierSolid = Color(hex: 0x6FA8DC)
    static let tierSkippable = Color(hex: 0x7A8592)
    static let favoriteAccent = Color(hex: 0xB388FF)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.dark
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
