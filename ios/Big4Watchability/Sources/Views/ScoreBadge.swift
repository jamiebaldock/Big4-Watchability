import SwiftUI

// Tier-colored score pill - now only used by AboutView's tier legend
// (GamesView/StarredView/HistoryView moved to TierBadge via GameCardView,
// matching Android's actual on-tile badge).
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

    private var tint: Color { tier.color }
}
