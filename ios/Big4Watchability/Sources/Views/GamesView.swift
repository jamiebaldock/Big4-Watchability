import SwiftUI

// Swift mirror of DayTabsScreen.kt - day-tab strip + swipeable multi-day
// pager, calendar jump-to-date, jump-to-today, jump-to-next-game, and the
// rating/date sort toggle. Not attempted: Android's "busiest day of the
// year" banner and full-season prefetch (this port's GamesViewModel
// extends its window by simple chunked fetches instead - see that file).
struct GamesView: View {
    @StateObject private var viewModel = GamesViewModel()
    @ObservedObject private var push = PushNotificationManager.shared
    @ObservedObject private var favorites = FavoritesStore.shared
    @ObservedObject private var appSettings = AppSettingsStore.shared
    @ObservedObject private var weightsStore = RubricWeightsStore.shared
    @ObservedObject private var mlbWeightsStore = MlbRubricWeightsStore.shared
    @ObservedObject private var nflWeightsStore = NflRubricWeightsStore.shared
    @ObservedObject private var nhlWeightsStore = NhlRubricWeightsStore.shared
    @ObservedObject private var starred = StarredGamesStore.shared
    @Environment(\.appTheme) private var theme
    @AppStorage(AppSettingsKeys.showNumericScore) private var showNumericScore = true
    @AppStorage(AppSettingsKeys.bumpFavoriteTeamGames) private var bumpFavoriteTeamGames = true
    @AppStorage(AppSettingsKeys.wifiOnlyHighlights) private var wifiOnlyHighlights = false
    @AppStorage(AppSettingsKeys.confettiEnabled) private var confettiEnabled = true
    @AppStorage(AppSettingsKeys.minTierFilterEnabled) private var minTierFilterEnabled = false
    @AppStorage(AppSettingsKeys.minTierFilter) private var minTierFilterRawValue = WatchabilityTier.skippable.rawValue
    @AppStorage(AppSettingsKeys.defaultGameDetailTab) private var defaultGameDetailTabRawValue = GameDetailTab.breakdown.rawValue
    @State private var selectedHighlightsVideoId: String?
    @State private var selectedGameForDetail: GameJson?
    @State private var showCalendar = false

    private var allLeagues: Bool { appSettings.isAllLeaguesSelected }

    /// Consumes a pending alert deep link: switch league if the alert names a
    /// different one, then jump to the game's own day. Cleared up front so a
    /// second tap on the same game still re-triggers, and so the two call
    /// sites (`.task` and `.onChange`) can't both act on one link.
    private func consumeDeepLink() async {
        guard let link = push.pendingDeepLink else { return }
        push.pendingDeepLink = nil
        if let league = link.leagueGroup, league != viewModel.leagueGroup {
            viewModel.leagueGroup = league
        }
        if let utc = link.tipoffUtc, let tipoff = GameCardView.parseUtc(utc) {
            await viewModel.jumpToDate(tipoff, allLeagues: allLeagues)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !viewModel.days.isEmpty {
                    DayTabRow(
                        days: viewModel.days,
                        today: viewModel.today,
                        selectedIndex: viewModel.selectedDayIndex,
                        onSelect: { viewModel.selectDay($0, allLeagues: allLeagues) }
                    )
                }
                content
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TitleLeagueSelector(
                        selectedLeague: viewModel.leagueGroup,
                        onLeagueSelected: { league in
                            appSettings.isAllLeaguesSelected = false
                            viewModel.leagueGroup = league
                        },
                        isAllLeaguesSelected: allLeagues,
                        onAllLeaguesSelected: { appSettings.isAllLeaguesSelected = true }
                    )
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if currentDayDate?.apiDateString != viewModel.today.apiDateString {
                        Button {
                            Task { await viewModel.jumpToToday(allLeagues: allLeagues) }
                        } label: {
                            if viewModel.isJumpingToToday {
                                ProgressView()
                            } else {
                                Image(systemName: "calendar.badge.clock")
                            }
                        }
                        .disabled(viewModel.isJumpingToToday)
                    }
                    Button {
                        showCalendar = true
                    } label: {
                        if viewModel.isJumpingToDate {
                            ProgressView()
                        } else {
                            Image(systemName: "calendar")
                        }
                    }
                    .disabled(viewModel.isJumpingToDate)
                    SortMenuButton(
                        selected: viewModel.sortOption,
                        onSelected: { viewModel.sortOption = $0 },
                        ratingSortEnabled: currentDayHasRatedGame
                    )
                    Button {
                        showNumericScore.toggle()
                    } label: {
                        Image(systemName: "number")
                    }
                    .foregroundStyle(currentDayHasRatedGame ? (showNumericScore ? AppColors.tierWorthYourTime : theme.textSecondary) : theme.textSecondary.opacity(0.35))
                    .disabled(!currentDayHasRatedGame)
                }
            }
            .toolbarBackground(theme.backgroundBase, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                await viewModel.load(allLeagues: allLeagues)
                // Also consumed here, not just in the onChange below: if the
                // notification is tapped while another tab is showing, the
                // link is already set by the time this view first appears, so
                // the onChange never fires for it.
                await consumeDeepLink()
            }
            .onChange(of: viewModel.leagueGroup) { _ in
                Task { await viewModel.load(allLeagues: allLeagues) }
            }
            .onChange(of: appSettings.isAllLeaguesSelected) { _ in
                Task { await viewModel.load(allLeagues: allLeagues) }
            }
            // A tapped alert deep-links here. RootView has already switched
            // to this tab; consuming the link is GamesView's job because it
            // owns the GamesViewModel that knows how to jump. Cleared
            // immediately so a second tap on the same game still works.
            .onChange(of: push.pendingDeepLink) { _ in
                Task { await consumeDeepLink() }
            }
            .sheet(isPresented: $showCalendar) {
                SeasonCalendarView(
                    initialMonth: currentDayDate ?? viewModel.today,
                    viewModel: viewModel,
                    onMonthChanged: { month in Task { await viewModel.loadMonthCounts(month: month, allLeagues: allLeagues) } },
                    onDateSelected: { date in Task { await viewModel.jumpToDate(date, allLeagues: allLeagues) } }
                )
            }
            .alert("Couldn't jump to next game", isPresented: Binding(
                get: { viewModel.jumpToNextGameError != nil },
                set: { if !$0 { viewModel.jumpToNextGameError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.jumpToNextGameError ?? "")
            }
            .fullScreenCover(isPresented: Binding(
                get: { selectedHighlightsVideoId != nil },
                set: { if !$0 { selectedHighlightsVideoId = nil } }
            )) {
                if let videoId = selectedHighlightsVideoId {
                    HighlightsPlayerView(videoId: videoId, wifiOnlyEnabled: wifiOnlyHighlights)
                }
            }
            .sheet(item: $selectedGameForDetail) { game in
                GameDetailView(
                    game: game,
                    nbaWeights: weightsStore.weights(for: LeagueGroup(espnLeague: game.lg)),
                    wnbaWeights: weightsStore.weights(for: .wnba),
                    mlbWeights: mlbWeightsStore.weights,
                    nflWeights: nflWeightsStore.weights,
                    nhlWeights: nhlWeightsStore.weights,
                    defaultTab: GameDetailTab(rawValue: defaultGameDetailTabRawValue) ?? .breakdown,
                    onWatchHighlights: { videoId in
                        selectedGameForDetail = nil
                        selectedHighlightsVideoId = videoId
                    }
                )
            }
        }
    }

    private var currentDayDate: Date? {
        guard viewModel.days.indices.contains(viewModel.selectedDayIndex) else { return nil }
        return Date.fromApiDateString(viewModel.days[viewModel.selectedDayIndex].date)
    }

    private var currentDayHasRatedGame: Bool {
        guard viewModel.days.indices.contains(viewModel.selectedDayIndex) else { return false }
        return viewModel.days[viewModel.selectedDayIndex].games.contains {
            $0.effectiveScoreAndTier(
                nba: weightsStore.weights(for: LeagueGroup(espnLeague: $0.lg)),
                mlb: mlbWeightsStore.weights,
                nfl: nflWeightsStore.weights,
                nhl: nhlWeightsStore.weights
            ) != nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.days.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.backgroundBase)
        } else if let message = viewModel.errorMessage, viewModel.days.isEmpty {
            EmptyStateView(title: message, systemImage: "wifi.slash")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.backgroundBase)
        } else {
            TabView(selection: dayIndexBinding) {
                ForEach(Array(viewModel.days.enumerated()), id: \.element.id) { index, day in
                    DayGamesListView(
                        games: displayedGames(for: day),
                        isJumpingToNextGame: viewModel.isJumpingToNextGame,
                        onJumpToNextGame: { Task { await viewModel.jumpToNextGame(allLeagues: allLeagues) } },
                        showNumericScore: showNumericScore,
                        confettiEnabled: confettiEnabled,
                        starred: starred,
                        weightsStore: weightsStore,
                        mlbWeightsStore: mlbWeightsStore,
                        nflWeightsStore: nflWeightsStore,
                        nhlWeightsStore: nhlWeightsStore,
                        onTap: { selectedGameForDetail = $0 },
                        onWatchHighlights: { selectedHighlightsVideoId = $0 },
                        onRefresh: { await viewModel.refresh(allLeagues: allLeagues) }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(theme.backgroundBase)
        }
    }

    private var dayIndexBinding: Binding<Int> {
        Binding(
            get: { viewModel.selectedDayIndex },
            set: { viewModel.selectDay($0, allLeagues: allLeagues) }
        )
    }

    // Mirrors DayGamesList's sort/filter/bump pipeline in DayTabsScreen.kt.
    private func displayedGames(for day: DayGames) -> [GameJson] {
        var games = day.games
        switch viewModel.sortOption {
        case .dateOldestFirst:
            games.sort { $0.utc < $1.utc }
        case .dateNewestFirst:
            games.sort { $0.utc > $1.utc }
        case .ratingHighestFirst:
            let (scored, unscored) = partitionByScore(games)
            games = scored.sorted { (scoreOf($0) ?? 0) > (scoreOf($1) ?? 0) } + unscored.sorted { $0.utc > $1.utc }
        case .ratingLowestFirst:
            let (scored, unscored) = partitionByScore(games)
            games = scored.sorted { (scoreOf($0) ?? 0) < (scoreOf($1) ?? 0) } + unscored.sorted { $0.utc > $1.utc }
        }

        games = games.filteredByMinTier(
            enabled: minTierFilterEnabled,
            minTier: WatchabilityTier(rawValue: minTierFilterRawValue) ?? .skippable,
            nba: { weightsStore.weights(for: LeagueGroup(espnLeague: $0.lg)) },
            mlb: mlbWeightsStore.weights,
            nfl: nflWeightsStore.weights,
            nhl: nhlWeightsStore.weights
        )

        guard bumpFavoriteTeamGames else { return games }
        let favoriteNames = Set(
            favorites.teams
                .filter { allLeagues || $0.leagueGroup == viewModel.leagueGroup }
                .map { $0.team.name }
        )
        guard !favoriteNames.isEmpty else { return games }
        let (favored, rest) = games.reduce(into: ([GameJson](), [GameJson]())) { result, game in
            if favoriteNames.contains(game.a) || favoriteNames.contains(game.h) {
                result.0.append(game)
            } else {
                result.1.append(game)
            }
        }
        return favored + rest
    }

    private func scoreOf(_ game: GameJson) -> Int? {
        game.effectiveScoreAndTier(
            nba: weightsStore.weights(for: LeagueGroup(espnLeague: game.lg)),
            mlb: mlbWeightsStore.weights,
            nfl: nflWeightsStore.weights,
            nhl: nhlWeightsStore.weights
        )?.score
    }

    private func partitionByScore(_ games: [GameJson]) -> (scored: [GameJson], unscored: [GameJson]) {
        var scored: [GameJson] = []
        var unscored: [GameJson] = []
        for game in games {
            if scoreOf(game) != nil { scored.append(game) } else { unscored.append(game) }
        }
        return (scored, unscored)
    }
}

// Swift mirror of DayTabsScreen.kt's CenteringDayTabRow - a horizontally
// scrollable strip of day chips (Yesterday/Today/Tomorrow/[EEE MMM d]),
// auto-scrolling to keep the selected chip in view.
private struct DayTabRow: View {
    let days: [DayGames]
    let today: Date
    let selectedIndex: Int
    let onSelect: (Int) -> Void

    private static let labelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d"
        return f
    }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                        NavChip(
                            label: label(for: day),
                            selected: index == selectedIndex,
                            onClick: { onSelect(index) }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onAppear { proxy.scrollTo(selectedIndex, anchor: .center) }
            .onChange(of: selectedIndex) { newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    private func label(for day: DayGames) -> String {
        guard let date = Date.fromApiDateString(day.date) else { return day.date }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: today) { return "Today" }
        if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: today) ?? today) { return "Yesterday" }
        if calendar.isDate(date, inSameDayAs: calendar.date(byAdding: .day, value: 1, to: today) ?? today) { return "Tomorrow" }
        return Self.labelFormatter.string(from: date)
    }
}

private struct NavChip: View {
    let label: String
    let selected: Bool
    let onClick: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onClick) {
            Text(label)
                .font(.subheadline.bold())
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? theme.backgroundBase : theme.textPrimary)
                .background(selected ? AppColors.tierWorthYourTime : theme.surfaceCardElevated, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// Swift mirror of DayTabsScreen.kt's DayGamesList - one day's ordered tile
// list, or an empty state with a "Jump to next game" action.
private struct DayGamesListView: View {
    let games: [GameJson]
    let isJumpingToNextGame: Bool
    let onJumpToNextGame: () -> Void
    let showNumericScore: Bool
    let confettiEnabled: Bool
    @ObservedObject var starred: StarredGamesStore
    @ObservedObject var weightsStore: RubricWeightsStore
    @ObservedObject var mlbWeightsStore: MlbRubricWeightsStore
    @ObservedObject var nflWeightsStore: NflRubricWeightsStore
    @ObservedObject var nhlWeightsStore: NhlRubricWeightsStore
    let onTap: (GameJson) -> Void
    let onWatchHighlights: (String) -> Void
    let onRefresh: () async -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        if games.isEmpty {
            VStack(spacing: 20) {
                Text("No games scheduled")
                    .font(.title3.bold())
                    .foregroundStyle(theme.textSecondary)
                Button(action: onJumpToNextGame) {
                    if isJumpingToNextGame {
                        ProgressView()
                    } else {
                        Text("Jump to next game")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.tierWorthYourTime)
                .disabled(isJumpingToNextGame)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .background(theme.backgroundBase)
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(games) { game in
                        GameCardView(
                            game: game,
                            showNumericScore: showNumericScore,
                            scoreAndTier: game.effectiveScoreAndTier(
                                nba: weightsStore.weights(for: LeagueGroup(espnLeague: game.lg)),
                                mlb: mlbWeightsStore.weights,
                                nfl: nflWeightsStore.weights,
                                nhl: nhlWeightsStore.weights
                            ),
                            confettiEnabled: confettiEnabled,
                            isStarred: starred.isStarred(game),
                            onToggleStar: { starred.toggle(game) },
                            onTap: { onTap(game) },
                            onWatchHighlights: onWatchHighlights,
                            // Games is the only tab with the bell, matching
                            // Android's showBell usage.
                            showBell: true
                        )
                    }
                }
                .padding(16)
            }
            .background(theme.backgroundBase)
            .refreshable { await onRefresh() }
        }
    }
}

#Preview {
    GamesView()
}
