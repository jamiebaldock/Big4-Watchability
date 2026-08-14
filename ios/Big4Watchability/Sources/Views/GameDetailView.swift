import SwiftUI

// Swift mirror of GameDetailScreen.kt - tap-a-tile popup, only ever opened
// for a FINAL, already-rated game (callers gate on game.hasBreakdown before
// presenting this at all, since an upcoming/live game has neither a rubric
// breakdown nor real top-performer stats to show yet).
enum GameDetailTab: String {
    case breakdown, topPerformers
}

struct GameDetailView: View {
    let game: GameJson
    let nbaWeights: RubricWeights
    let wnbaWeights: RubricWeights
    let mlbWeights: MlbRubricWeights
    let nflWeights: NflRubricWeights
    let nhlWeights: NhlRubricWeights
    var defaultTab: GameDetailTab = .breakdown
    var onWatchHighlights: (String) -> Void = { _ in }

    @StateObject private var viewModel = GameDetailViewModel()
    @State private var selectedTab: GameDetailTab
    @Environment(\.dismiss) private var dismiss

    init(
        game: GameJson,
        nbaWeights: RubricWeights,
        wnbaWeights: RubricWeights,
        mlbWeights: MlbRubricWeights,
        nflWeights: NflRubricWeights,
        nhlWeights: NhlRubricWeights,
        defaultTab: GameDetailTab = .breakdown,
        onWatchHighlights: @escaping (String) -> Void = { _ in }
    ) {
        self.game = game
        self.nbaWeights = nbaWeights
        self.wnbaWeights = wnbaWeights
        self.mlbWeights = mlbWeights
        self.nflWeights = nflWeights
        self.nhlWeights = nhlWeights
        self.defaultTab = defaultTab
        self.onWatchHighlights = onWatchHighlights
        _selectedTab = State(initialValue: defaultTab)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let videoId = game.yt {
                        HighlightsRow(onWatch: { onWatchHighlights(videoId) })
                        Divider()
                    }

                    Picker("Tab", selection: $selectedTab) {
                        Text("Breakdown").tag(GameDetailTab.breakdown)
                        Text("Top Performers").tag(GameDetailTab.topPerformers)
                    }
                    .pickerStyle(.segmented)

                    switch selectedTab {
                    case .breakdown:
                        BreakdownTab(
                            game: game,
                            nbaWeights: nbaWeights,
                            wnbaWeights: wnbaWeights,
                            mlbWeights: mlbWeights,
                            nflWeights: nflWeights,
                            nhlWeights: nhlWeights
                        )
                    case .topPerformers:
                        TopPerformersTab(uiState: viewModel.uiState, onRetry: viewModel.retry)
                    }

                    Divider().padding(.vertical, 8)

                    ContextSection(uiState: viewModel.uiState, onRetry: viewModel.retry)
                }
                .padding()
            }
            .navigationTitle("\(game.al ?? game.a) at \(game.hl ?? game.h)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: game.eventId) {
            if let eventId = game.eventId {
                viewModel.load(eventId: eventId)
            }
        }
    }

    private var shareText: String {
        var text = "\(game.al ?? game.a) @ \(game.hl ?? game.h)"
        if let awayScore = game.awayScore, let homeScore = game.homeScore {
            text += " (\(awayScore)-\(homeScore))"
        }
        if let scoreAndTier = game.effectiveScoreAndTier(nba: nbaWeights, mlb: mlbWeights, nfl: nflWeights, nhl: nhlWeights) {
            text += " - \(scoreAndTier.tier.label) (\(scoreAndTier.score)/100)"
        }
        return text
    }
}

private struct HighlightsRow: View {
    let onWatch: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "play.circle.fill")
                .foregroundStyle(.orange)
            Text("Watch highlights")
                .foregroundStyle(.orange)
            Spacer()
            Button("Watch", action: onWatch)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct BreakdownTab: View {
    let game: GameJson
    let nbaWeights: RubricWeights
    let wnbaWeights: RubricWeights
    let mlbWeights: MlbRubricWeights
    let nflWeights: NflRubricWeights
    let nhlWeights: NhlRubricWeights

    var body: some View {
        let entries = game.rubricBreakdown(nba: nbaWeights, wnba: wnbaWeights, mlb: mlbWeights, nfl: nflWeights, nhl: nhlWeights)
        let total = game.effectiveScoreAndTier(nba: nbaWeights, mlb: mlbWeights, nfl: nflWeights, nhl: nhlWeights)?.score ?? 0

        VStack(alignment: .leading, spacing: 6) {
            ForEach(entries) { entry in
                HStack {
                    Text(entry.label)
                    Spacer()
                    Text("\(Int(entry.points.rounded()))/\(Int(entry.maxPoints.rounded())) pts")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
            Divider().padding(.vertical, 4)
            HStack {
                Text("Total watchability").font(.headline)
                Spacer()
                Text("\(total)/100")
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .monospacedDigit()
            }
        }
    }
}

private struct TopPerformersTab: View {
    let uiState: GameDetailUiState
    let onRetry: () -> Void

    var body: some View {
        switch uiState {
        case .loading:
            LoadingRow()
        case .error(let message):
            ErrorRow(message: message, onRetry: onRetry)
        case .loaded(let data):
            if data.topPerformers.isEmpty {
                Text("No standout individual stats for this game.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(data.topPerformers) { performer in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(performer.name).font(.body)
                            Text("\(performer.team) - \(performer.line)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

private struct ContextSection: View {
    let uiState: GameDetailUiState
    let onRetry: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    var body: some View {
        switch uiState {
        case .loading:
            LoadingRow()
        case .error:
            EmptyView() // Top Performers tab already surfaces this same error/retry
        case .loaded(let data):
            VStack(alignment: .leading, spacing: 16) {
                if data.awayStandings.record != nil || data.homeStandings.record != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Standings").font(.subheadline.bold())
                        if let record = data.awayStandings.record {
                            Text("\(data.awayStandings.groupName ?? ""): #\(data.awayStandings.rank ?? 0) (\(record))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let record = data.homeStandings.record {
                            Text("\(data.homeStandings.groupName ?? ""): #\(data.homeStandings.rank ?? 0) (\(record))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !data.headToHead.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Head-to-head this season").font(.subheadline.bold())
                        ForEach(data.headToHead) { meeting in
                            Text("\(formattedDate(meeting.utc)): \(meeting.away) \(meeting.awayScore) - \(meeting.homeScore) \(meeting.home)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func formattedDate(_ iso: String) -> String {
        // The backend's toISOString() always includes fractional seconds
        // (e.g. "2026-08-14T18:30:00.000Z") - the plain-Internet-time
        // formatter alone fails to parse that, so try fractional first.
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: iso) {
            return Self.dateFormatter.string(from: date)
        }
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return Self.dateFormatter.string(from: date)
    }
}

private struct LoadingRow: View {
    var body: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 16)
    }
}

private struct ErrorRow: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
