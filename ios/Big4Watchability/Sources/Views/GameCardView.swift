import SwiftUI

// Swift mirror of GameCard.kt's visual structure - the shared card used by
// Games, Starred and History (each previously rendered a plain one-line
// Text row instead, which is why the very first real-device look at this
// app showed nothing like Android's actual design). Not a 1:1 port of every
// feature (favorite-team long-press tint, GOAT badge, add-highlight-link
// row) - just the core look: elevated card, tier-colored border, real team
// logos, tier badge, status indicator, hook/pitch text, highlights row.
struct GameCardView: View {
    let game: GameJson
    let showNumericScore: Bool
    let scoreAndTier: (score: Int, tier: WatchabilityTier)?
    let confettiEnabled: Bool
    var isStarred: Bool = false
    var onToggleStar: () -> Void = {}
    var showDate: Bool = false
    // History's "browse blind" toggle - hides just the numeric score digits,
    // not the tier badge. Always true elsewhere.
    var showScore: Bool = true
    var onTap: () -> Void = {}
    var onWatchHighlights: (String) -> Void = { _ in }

    @Environment(\.appTheme) private var theme
    @State private var showConfetti = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if game.cl != nil || showDate {
                HStack(spacing: 4) {
                    if let cl = game.cl {
                        Text(cl)
                            .font(.caption2.bold())
                            .foregroundStyle(theme.textMuted)
                    }
                    if showDate {
                        if game.cl != nil {
                            Text("-").font(.caption2).foregroundStyle(theme.textMuted)
                        }
                        Text(Self.localDateString(game.utc))
                            .font(.caption2)
                            .foregroundStyle(theme.textMuted)
                    }
                }
            }

            HStack {
                if game.scoreVisible, let scoreAndTier {
                    TierBadge(tier: scoreAndTier.tier, numericScore: showNumericScore ? scoreAndTier.score : nil)
                }
                Spacer()
                StatusIndicatorView(game: game)
                Button(action: onToggleStar) {
                    Image(systemName: isStarred ? "star.fill" : "star")
                        .foregroundStyle(isStarred ? AppColors.tierInstantClassic : theme.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)
            }

            VStack(alignment: .leading, spacing: 4) {
                TeamRowView(logoUrl: game.al, name: game.a, score: showScore ? game.awayScore : nil)
                TeamRowView(logoUrl: game.hl, name: game.h, score: showScore ? game.homeScore : nil)
            }

            if game.stt == .final, let performers = game.sop, !performers.isEmpty {
                StandoutPerformerCallout(game: game, performers: performers)
            }

            if game.stt != .final {
                Text(pitchText)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }

            if game.stt == .final, let videoId = game.yt {
                Button {
                    onWatchHighlights(videoId)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle.fill")
                        Text("Watch highlights").bold()
                        Text("· Spoiler alert").foregroundStyle(theme.textMuted)
                    }
                    .font(.subheadline)
                    .foregroundStyle(AppColors.tierWorthYourTime)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surfaceCardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke((game.scoreVisible ? scoreAndTier?.tier.color : nil) ?? .clear, lineWidth: 1.5)
        )
        .overlay(alignment: .topLeading) {
            if showConfetti {
                ConfettiBurst(onFinished: { showConfetti = false })
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if game.hasBreakdown {
                onTap()
            } else if let videoId = game.yt {
                onWatchHighlights(videoId)
            }
        }
        .task(id: "\(game.id)-\(scoreAndTier?.tier.rawValue ?? "")-\(game.stt.rawValue)") {
            guard let scoreAndTier, scoreAndTier.tier == .instantClassic, game.stt == .final else { return }
            guard InstantClassicCelebrationTracker.markIfFirstTime(game.id) else { return }
            if confettiEnabled {
                showConfetti = true
                fireInstantClassicHaptic()
            }
        }
    }

    private var pitchText: String {
        if let pitch = game.pitch, !pitch.isEmpty, pitch != game.hook {
            return "\(game.hook) \(pitch)"
        }
        return game.hook
    }

    // ESPN omits the seconds field when it's :00 (e.g. "19:30Z" not
    // "19:30:00Z") - ISO8601DateFormatter's strict internet-date-time mode
    // rejects that shape, so fall back to a manual UTC formatter for it
    // (same root cause Android's own localTipoff/localDate comment
    // documents against OffsetDateTime.parse).
    static func parseUtc(_ iso: String) -> Date? {
        let strict = ISO8601DateFormatter()
        strict.formatOptions = [.withInternetDateTime]
        if let date = strict.date(from: iso) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: iso) { return date }
        let noSeconds = DateFormatter()
        noSeconds.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        noSeconds.timeZone = TimeZone(identifier: "UTC")
        return noSeconds.date(from: iso)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    static func localTipoffTime(_ utc: String) -> String {
        guard let date = parseUtc(utc) else { return utc }
        return timeFormatter.string(from: date)
    }

    static func localDateString(_ utc: String) -> String {
        guard let date = parseUtc(utc) else { return utc }
        return dateFormatter.string(from: date)
    }
}

private struct TeamRowView: View {
    let logoUrl: String?
    let name: String
    let score: Int?

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            if let logoUrl, let url = URL(string: logoUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 24, height: 24)
            }
            Text(name)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let score {
                Text("\(score)")
                    .font(.system(size: 20, weight: .bold).monospacedDigit())
                    .foregroundStyle(theme.textPrimary)
                    .padding(.leading, 2)
            }
        }
    }
}

private struct StatusIndicatorView: View {
    let game: GameJson

    @Environment(\.appTheme) private var theme
    @State private var pulseDim = false

    var body: some View {
        switch game.stt {
        case .live:
            HStack(spacing: 4) {
                Circle()
                    .fill(AppColors.liveRed)
                    .frame(width: 8, height: 8)
                    .opacity(pulseDim ? 0.3 : 1)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            pulseDim = true
                        }
                    }
                Text("LIVE")
                    .font(.caption.bold())
                    .foregroundStyle(AppColors.liveRed)
                if let clock = game.clk, let q = game.q {
                    Text("Q\(q) \(clock)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.textSecondary)
                }
            }
        case .upcoming:
            Text(GameCardView.localTipoffTime(game.utc))
                .font(.caption.monospacedDigit())
                .foregroundStyle(theme.textSecondary)
        case .final:
            Text("FINAL")
                .font(.caption.bold())
                .foregroundStyle(theme.textMuted)
        }
    }
}
