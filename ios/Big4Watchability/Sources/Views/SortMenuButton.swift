import SwiftUI

// Swift mirror of SortMenu.kt's SortMenuButton - two independent toggle
// buttons (rating order via a "#" icon, date order via a calendar icon),
// each with a small up/down arrow badge showing its current direction.
// Tapping the axis that's already active flips its direction; tapping the
// other axis switches the active sort to it, defaulting to the more useful
// first look at that axis (highest-rated-first / oldest-first).
struct SortMenuButton: View {
    let selected: SortOption
    let onSelected: (SortOption) -> Void
    var ratingSortEnabled: Bool = true

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            SortToggleButton(
                systemImage: "number",
                isActive: ratingSortEnabled && (selected == .ratingHighestFirst || selected == .ratingLowestFirst),
                pointsUp: selected == .ratingLowestFirst,
                enabled: ratingSortEnabled,
                theme: theme,
                onClick: {
                    onSelected(selected == .ratingHighestFirst ? .ratingLowestFirst : .ratingHighestFirst)
                }
            )
            SortToggleButton(
                systemImage: "calendar",
                isActive: selected == .dateOldestFirst || selected == .dateNewestFirst,
                pointsUp: selected != .dateNewestFirst,
                enabled: true,
                theme: theme,
                onClick: {
                    onSelected(selected == .dateOldestFirst ? .dateNewestFirst : .dateOldestFirst)
                }
            )
        }
    }
}

private struct SortToggleButton: View {
    let systemImage: String
    let isActive: Bool
    let pointsUp: Bool
    let enabled: Bool
    let theme: AppTheme
    let onClick: () -> Void

    private var tint: Color {
        if !enabled { return theme.textSecondary.opacity(0.35) }
        return isActive ? AppColors.tierWorthYourTime : theme.textSecondary
    }

    var body: some View {
        Button(action: onClick) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 28, height: 28)
                Image(systemName: pointsUp ? "arrow.up" : "arrow.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
