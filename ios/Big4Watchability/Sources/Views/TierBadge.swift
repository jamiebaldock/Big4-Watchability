import SwiftUI

// Swift mirror of TierBadge.kt - outlined pill, tier-colored border and
// text on a transparent fill, monospaced with wide tracking. numericScore
// is only ever passed when the user's numeric-score toggle is on.
struct TierBadge: View {
    let tier: WatchabilityTier
    var numericScore: Int?

    var body: some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced).bold())
            .kerning(1.5)
            .foregroundStyle(tier.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tier.color, lineWidth: 1)
            )
    }

    private var text: String {
        if let numericScore {
            return "\(tier.emoji) \(tier.label) · \(numericScore)"
        }
        return "\(tier.emoji) \(tier.label)"
    }
}
