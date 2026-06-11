import SwiftUI

// MARK: - Theme enum

enum AppTheme: String, CaseIterable, Identifiable {
    case `default`          = "default"
    case clayCourt          = "clayCourt"
    case grassCourt         = "grassCourt"
    case hardCourtDay       = "hardCourtDay"
    case hardCourtNight     = "hardCourtNight"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:         return "Classic"
        case .clayCourt:       return "Clay Court"
        case .grassCourt:      return "Grass Court"
        case .hardCourtDay:    return "Hard Court"
        case .hardCourtNight:  return "Hard Court (Night)"
        }
    }

    var colors: ThemeColors {
        switch self {
        case .default:         return .classic
        case .clayCourt:       return .clayCourt
        case .grassCourt:      return .grassCourt
        case .hardCourtDay:    return .hardCourtDay
        case .hardCourtNight:  return .hardCourtNight
        }
    }
}

// MARK: - Color slots

struct ThemeColors {
    // Scoreboard panel
    let surface:     Color
    let meRow:       Color
    let opponentRow: Color

    // Player accents (scores, stats bars, labels)
    let me:       Color
    let opponent: Color

    // Server indicator
    let server: Color

    // Mini-court fill + stroke when me / opponent / no server
    let meCourt:             Color
    let opponentCourt:       Color
    let neutralCourt:        Color
    let meCourtStroke:       Color
    let opponentCourtStroke: Color
    let neutralCourtStroke:  Color

    // Watch home-screen button gradients
    let buttonPrimary:        LinearGradient
    let buttonServerMe:       LinearGradient
    let buttonServerOpponent: LinearGradient
}

// MARK: - Palette definitions

extension ThemeColors {

    // Classic — the original dark green / blue palette
    static let classic = ThemeColors(
        surface:              Color(red: 0.12, green: 0.13, blue: 0.16),
        meRow:                Color(red: 0.13, green: 0.28, blue: 0.18),
        opponentRow:          Color(red: 0.14, green: 0.18, blue: 0.28),
        me:                   Color(red: 0.20, green: 0.76, blue: 0.51),
        opponent:             Color(red: 0.26, green: 0.54, blue: 0.93),
        server:               Color(red: 0.96, green: 0.83, blue: 0.24),
        meCourt:              Color(red: 0.16, green: 0.44, blue: 0.28),
        opponentCourt:        Color(red: 0.20, green: 0.32, blue: 0.56),
        neutralCourt:         Color(red: 0.17, green: 0.38, blue: 0.23),
        meCourtStroke:        Color(red: 0.26, green: 0.64, blue: 0.42),
        opponentCourtStroke:  Color(red: 0.34, green: 0.54, blue: 0.82),
        neutralCourtStroke:   Color(red: 0.30, green: 0.62, blue: 0.36),
        buttonPrimary:        LinearGradient(
            colors: [Color(red: 0.25, green: 0.80, blue: 0.71),
                     Color(red: 0.08, green: 0.52, blue: 0.92)],
            startPoint: .topLeading, endPoint: .bottomTrailing),
        buttonServerMe:       LinearGradient(
            colors: [Color(red: 0.36, green: 0.78, blue: 0.37),
                     Color(red: 0.20, green: 0.60, blue: 0.24)],
            startPoint: .topLeading, endPoint: .bottomTrailing),
        buttonServerOpponent: LinearGradient(
            colors: [Color(red: 0.22, green: 0.40, blue: 0.82),
                     Color(red: 0.14, green: 0.26, blue: 0.60)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    )

    // Clay Court — terracotta orange + chalk sand on dark earth
    static let clayCourt = ThemeColors(
        surface:              Color(red: 0.12, green: 0.08, blue: 0.06),
        meRow:                Color(red: 0.22, green: 0.12, blue: 0.06),
        opponentRow:          Color(red: 0.20, green: 0.17, blue: 0.09),
        me:                   Color(red: 0.96, green: 0.54, blue: 0.22),
        opponent:             Color(red: 0.90, green: 0.82, blue: 0.58),
        server:               Color(red: 0.98, green: 0.88, blue: 0.42),
        meCourt:              Color(red: 0.42, green: 0.22, blue: 0.08),
        opponentCourt:        Color(red: 0.36, green: 0.30, blue: 0.12),
        neutralCourt:         Color(red: 0.30, green: 0.18, blue: 0.08),
        meCourtStroke:        Color(red: 0.72, green: 0.38, blue: 0.16),
        opponentCourtStroke:  Color(red: 0.72, green: 0.64, blue: 0.36),
        neutralCourtStroke:   Color(red: 0.58, green: 0.32, blue: 0.14),
        buttonPrimary:        LinearGradient(
            colors: [Color(red: 0.96, green: 0.54, blue: 0.22),
                     Color(red: 0.78, green: 0.36, blue: 0.10)],
            startPoint: .topLeading, endPoint: .bottomTrailing),
        buttonServerMe:       LinearGradient(
            colors: [Color(red: 0.96, green: 0.54, blue: 0.22),
                     Color(red: 0.78, green: 0.36, blue: 0.10)],
            startPoint: .topLeading, endPoint: .bottomTrailing),
        buttonServerOpponent: LinearGradient(
            colors: [Color(red: 0.72, green: 0.64, blue: 0.38),
                     Color(red: 0.54, green: 0.48, blue: 0.24)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    )

    // Grass Court — purple + green on near-black
    static let grassCourt = ThemeColors(
        surface:              Color(red: 0.06, green: 0.08, blue: 0.07),
        meRow:                Color(red: 0.18, green: 0.08, blue: 0.24),
        opponentRow:          Color(red: 0.08, green: 0.20, blue: 0.12),
        me:                   Color(red: 0.55, green: 0.22, blue: 0.78),
        opponent:             Color(red: 0.20, green: 0.74, blue: 0.40),
        server:               Color(red: 0.97, green: 0.96, blue: 0.84),
        meCourt:              Color(red: 0.28, green: 0.12, blue: 0.40),
        opponentCourt:        Color(red: 0.10, green: 0.30, blue: 0.18),
        neutralCourt:         Color(red: 0.10, green: 0.18, blue: 0.12),
        meCourtStroke:        Color(red: 0.62, green: 0.30, blue: 0.86),
        opponentCourtStroke:  Color(red: 0.30, green: 0.82, blue: 0.50),
        neutralCourtStroke:   Color(red: 0.22, green: 0.48, blue: 0.30),
        buttonPrimary:        LinearGradient(
            colors: [Color(red: 0.55, green: 0.22, blue: 0.78),
                     Color(red: 0.40, green: 0.14, blue: 0.60)],
            startPoint: .topLeading, endPoint: .bottomTrailing),
        buttonServerMe:       LinearGradient(
            colors: [Color(red: 0.55, green: 0.22, blue: 0.78),
                     Color(red: 0.40, green: 0.14, blue: 0.60)],
            startPoint: .topLeading, endPoint: .bottomTrailing),
        buttonServerOpponent: LinearGradient(
            colors: [Color(red: 0.20, green: 0.74, blue: 0.40),
                     Color(red: 0.12, green: 0.56, blue: 0.28)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    )

    // Hard Court (Day) — sky blue + gold on deep navy
    static let hardCourtDay = ThemeColors(
        surface:              Color(red: 0.06, green: 0.08, blue: 0.14),
        meRow:                Color(red: 0.06, green: 0.16, blue: 0.30),
        opponentRow:          Color(red: 0.24, green: 0.20, blue: 0.06),
        me:                   Color(red: 0.14, green: 0.58, blue: 0.94),
        opponent:             Color(red: 0.98, green: 0.76, blue: 0.12),
        server:               Color(red: 0.98, green: 0.82, blue: 0.14),
        meCourt:              Color(red: 0.08, green: 0.26, blue: 0.50),
        opponentCourt:        Color(red: 0.38, green: 0.30, blue: 0.06),
        neutralCourt:         Color(red: 0.08, green: 0.20, blue: 0.38),
        meCourtStroke:        Color(red: 0.22, green: 0.58, blue: 0.92),
        opponentCourtStroke:  Color(red: 0.98, green: 0.76, blue: 0.14),
        neutralCourtStroke:   Color(red: 0.18, green: 0.44, blue: 0.76),
        buttonPrimary:        LinearGradient(
            colors: [Color(red: 0.14, green: 0.58, blue: 0.94),
                     Color(red: 0.08, green: 0.38, blue: 0.74)],
            startPoint: .topLeading, endPoint: .bottomTrailing),
        buttonServerMe:       LinearGradient(
            colors: [Color(red: 0.14, green: 0.58, blue: 0.94),
                     Color(red: 0.08, green: 0.38, blue: 0.74)],
            startPoint: .topLeading, endPoint: .bottomTrailing),
        buttonServerOpponent: LinearGradient(
            colors: [Color(red: 0.84, green: 0.66, blue: 0.10),
                     Color(red: 0.66, green: 0.50, blue: 0.06)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    )

    // Hard Court (Night) — cobalt blue + chartreuse on very dark navy
    static let hardCourtNight = ThemeColors(
        surface:              Color(red: 0.04, green: 0.06, blue: 0.12),
        meRow:                Color(red: 0.08, green: 0.12, blue: 0.30),
        opponentRow:          Color(red: 0.18, green: 0.22, blue: 0.04),
        me:                   Color(red: 0.20, green: 0.34, blue: 0.92),
        opponent:             Color(red: 0.78, green: 0.94, blue: 0.14),
        server:               Color(red: 0.98, green: 0.96, blue: 0.92),
        meCourt:              Color(red: 0.12, green: 0.18, blue: 0.46),
        opponentCourt:        Color(red: 0.24, green: 0.30, blue: 0.06),
        neutralCourt:         Color(red: 0.08, green: 0.14, blue: 0.34),
        meCourtStroke:        Color(red: 0.30, green: 0.46, blue: 0.96),
        opponentCourtStroke:  Color(red: 0.78, green: 0.94, blue: 0.18),
        neutralCourtStroke:   Color(red: 0.20, green: 0.30, blue: 0.66),
        buttonPrimary:        LinearGradient(
            colors: [Color(red: 0.20, green: 0.34, blue: 0.92),
                     Color(red: 0.14, green: 0.24, blue: 0.72)],
            startPoint: .topLeading, endPoint: .bottomTrailing),
        buttonServerMe:       LinearGradient(
            colors: [Color(red: 0.20, green: 0.34, blue: 0.92),
                     Color(red: 0.14, green: 0.24, blue: 0.72)],
            startPoint: .topLeading, endPoint: .bottomTrailing),
        buttonServerOpponent: LinearGradient(
            colors: [Color(red: 0.72, green: 0.88, blue: 0.14),
                     Color(red: 0.56, green: 0.70, blue: 0.08)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    )
}

// MARK: - SwiftUI Environment key

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .default
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
