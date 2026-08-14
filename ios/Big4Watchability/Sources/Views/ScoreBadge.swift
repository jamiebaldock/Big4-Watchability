import SwiftUI

// Shared tier-colored score pill - used by GamesView and HistoryView (and
// anywhere else a game's watchability score gets displayed).
struct ScoreBadge: View {
    let score: Int
    let tier: WatchabilityTier
    let showNumber: Bool

    var body: some View {
        Group {
            if showNumber {
                Text("\(score)")
            } else {
                Circle().frame(width: 8, height: 8)
            }
        }
        .font(.caption.bold())
        .padding(.horizontal, showNumber ? 8 : 6)
        .padding(.vertical, 4)
        .background(tint.opacity(0.15), in: Capsule())
        .foregroundStyle(tint)
    }

    private var tint: Color {
        switch tier {
        case .instantClassic: return .red
        case .worthYourTime: return .orange
        case .solid: return .yellow
        case .skippable: return .gray
        }
    }
}
