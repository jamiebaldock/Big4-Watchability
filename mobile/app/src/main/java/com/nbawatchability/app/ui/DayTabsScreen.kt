package com.nbawatchability.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Today
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nbawatchability.app.data.DayGames
import com.nbawatchability.app.data.LeagueGroup
import com.nbawatchability.app.data.MlbRubricWeights
import com.nbawatchability.app.data.NflRubricWeights
import com.nbawatchability.app.data.NhlRubricWeights
import com.nbawatchability.app.data.RubricWeights
import com.nbawatchability.app.data.Team
import com.nbawatchability.app.data.Tier
import com.nbawatchability.app.data.bumpFavoriteTeamGames
import com.nbawatchability.app.data.effectiveScore
import com.nbawatchability.app.data.filterByMinTier
import com.nbawatchability.app.ui.theme.BackgroundBase
import com.nbawatchability.app.ui.theme.TextSecondary
import com.nbawatchability.app.ui.theme.TierInstantClassic
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

// Nothing hardcoded here anymore - which date(s) get the banner and how many
// games they had are both computed dynamically by GameListViewModel.kt's
// loadYearRecordDaysIfNeeded (real per-day counts, bucketed by the viewer's
// own local calendar date, same mechanism the calendar picker itself uses).
// See that function's own comment for why more than one date commonly ties
// for the year's real max, and why the specific tied date(s) can differ by a
// day depending on the viewer's own timezone relative to the US Eastern/
// ESPN-scoreboard-day convention the raw data comes back in.
@Composable
private fun RecordGameDayBanner(gameCount: Int, isTied: Boolean, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(TierInstantClassic.copy(alpha = 0.12f), RoundedCornerShape(10.dp))
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(imageVector = Icons.Default.EmojiEvents, contentDescription = null, tint = TierInstantClassic, modifier = Modifier.size(20.dp))
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = if (isTied) {
                "One of the busiest days of 2026 - $gameCount games across every league today"
            } else {
                "Busiest day of 2026 - $gameCount games across every league today"
            },
            color = TierInstantClassic,
            style = MaterialTheme.typography.labelMedium
        )
    }
}

private val dayTabFormatter = DateTimeFormatter.ofPattern("MMM d")

private fun dayTabLabel(date: LocalDate, today: LocalDate): String = when (date) {
    today -> "Today"
    today.minusDays(1) -> "Yesterday"
    today.plusDays(1) -> "Tomorrow"
    else -> "${date.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.getDefault())} ${date.format(dayTabFormatter)}"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DayTabsScreen(
    days: List<DayGames>,
    today: LocalDate,
    selectedDayIndex: Int,
    onDaySelected: (Int) -> Unit,
    showNumericScore: Boolean,
    onToggleNumericScore: () -> Unit,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    nbaWeights: RubricWeights,
    wnbaWeights: RubricWeights,
    mlbWeights: MlbRubricWeights,
    nflWeights: NflRubricWeights,
    nhlWeights: NhlRubricWeights,
    selectedLeague: LeagueGroup,
    onLeagueSelected: (LeagueGroup) -> Unit,
    enabledLeagues: Set<LeagueGroup>,
    isAllLeaguesSelected: Boolean,
    onToggleAllLeagues: () -> Unit,
    starredIds: Set<String>,
    onToggleStar: (com.nbawatchability.app.data.Game) -> Unit,
    onWatchHighlights: (String) -> Unit,
    isJumpingToNextGame: Boolean,
    jumpToNextGameError: String?,
    onJumpToNextGame: () -> Unit,
    onJumpToNextGameErrorShown: () -> Unit,
    isJumpingToToday: Boolean,
    onJumpToToday: () -> Unit,
    monthCounts: Map<LocalDate, Int>,
    monthCountsMonth: YearMonth?,
    isLoadingMonthCounts: Boolean,
    onMonthChanged: (YearMonth) -> Unit,
    recordDays: Set<LocalDate>,
    isJumpingToDate: Boolean,
    onJumpToDate: (LocalDate) -> Unit,
    favoriteTeamNames: Set<String> = emptySet(),
    bumpFavoriteTeamGames: Boolean = false,
    onToggleFavoriteTeam: (Team) -> Unit = {},
    favoritePlayerNames: Set<String> = emptySet(),
    onToggleFavoritePlayer: (com.nbawatchability.app.data.FavoritePlayer) -> Unit = {},
    minTierFilterEnabled: Boolean = false,
    minTierFilter: Tier = Tier.SKIPPABLE,
    onGameClick: (com.nbawatchability.app.data.Game) -> Unit = {},
    belledGameIds: Set<String> = emptySet(),
    onToggleBell: (com.nbawatchability.app.data.Game) -> Unit = {}
) {
    // Keyed on the loaded window's own shape (its first date + length), not
    // just remembered bare - GameListViewModel.load()'s two-phase fetch
    // swaps the narrow-window `days` list for the full-season one behind the
    // scenes (same landed-on DATE, but a different numeric index, since the
    // narrow and full windows start on different dates). A bare
    // rememberPagerState survives that swap with its OLD numeric
    // currentPage intact, so for at least one recomposition frame
    // HorizontalPager renders `days[oldPage]` against the NEW (bigger) list
    // - a real, confirmed (reproduced on-device) flash of the WRONG day's
    // games in the pager body a few seconds after first paint, before the
    // correction below ever gets a chance to run. Keying the state itself to
    // the window's shape sidesteps the whole problem: a shape change (this
    // swap, a league switch, or an out-of-window calendar jump) throws away
    // the old PagerState and builds a fresh one already positioned at
    // [selectedDayIndex] of the NEW list, so it's never wrong to begin with.
    // A plain in-window move (day-tab tap, swipe, jump to a date already
    // loaded) keeps the same shape/key, so the existing PagerState (and the
    // swipe gesture/settledPage sync below) is untouched.
    val windowShapeKey = days.firstOrNull()?.date to days.size
    val pagerState = key(windowShapeKey) {
        rememberPagerState(initialPage = selectedDayIndex) { days.size }
    }
    var actionLabel by remember { mutableStateOf<String?>(null) }
    var showCalendar by remember { mutableStateOf(false) }
    // One shared sort preference across every day, not a per-day setting -
    // matches the shared action-icon row above it (one control, not one per
    // page). Defaults to oldest-first (i.e. tipoff order), the natural
    // reading order for a single day's slate.
    var sortOption by remember { mutableStateOf(SortOption.DATE_OLDEST_FIRST) }
    // Both the rating-sort and numeric-score icons are meaningless on a day
    // where nothing is rated yet (a future day's slate) - shared here so
    // both actions below gate on the exact same condition.
    val currentDayHasRatedGame = days.getOrNull(selectedDayIndex)?.games.orEmpty().any {
        it.effectiveScore(nbaWeights, wnbaWeights, mlbWeights, nflWeights, nhlWeights) != null
    }

    // settledPage (not currentPage) drives the push-up-to-ViewModel side of
    // this sync deliberately - currentPage changes on every intermediate
    // page a programmatic animateScrollToPage animation crosses, and for a
    // far calendar-picker jump (e.g. today -> two months away) that's dozens
    // of pages. Syncing selectedDayIndex off currentPage fed each of those
    // transient pages back into the effect below, which re-triggered
    // animateScrollToPage toward that transient (wrong) target and
    // cancelled the in-flight one — producing exactly the stuck
    // half-settled/split-page state reported against the calendar picker.
    // settledPage only changes once the pager is done moving (swipe or
    // programmatic), so it can't reintroduce that loop. windowShapeKey is
    // included here (and below) purely so both effects are torn down and
    // relaunched in lockstep with pagerState's own key()-driven recreation
    // above - LaunchedEffect only restarts a coroutine when one of its keys
    // actually changes value, and settledPage's OWN value can easily
    // coincide with what it was under the old (now-replaced) PagerState,
    // which would otherwise leave this effect's closure silently pointing at
    // a stale, discarded pagerState instance.
    LaunchedEffect(windowShapeKey, pagerState.settledPage) {
        if (pagerState.settledPage != selectedDayIndex) onDaySelected(pagerState.settledPage)
    }
    // A window-SHAPE change (narrow-to-full swap, league switch, out-of-
    // window jump) is now handled entirely by pagerState's own key() above -
    // that always hands back a fresh PagerState already sitting on
    // [selectedDayIndex], so this effect never even sees a mismatch for that
    // case. What's left for this effect is a plain IN-window move (day-tab
    // tap, swipe settling, jump to an already-loaded date) on the SAME
    // PagerState instance, which still needs an actual animated scroll for
    // the visual feedback a deliberate move should have. lastPositionedDate
    // is kept mainly as a belt-and-suspenders guard against a same-date
    // reindex (e.g. a per-day content refresh that leaves the window shape,
    // and so the key, unchanged) snapping instead of animating.
    var lastPositionedDate by remember { mutableStateOf<LocalDate?>(null) }
    LaunchedEffect(windowShapeKey, selectedDayIndex, days) {
        val targetDate = days.getOrNull(selectedDayIndex)?.date
        if (pagerState.currentPage != selectedDayIndex) {
            if (targetDate != null && targetDate == lastPositionedDate) {
                pagerState.scrollToPage(selectedDayIndex)
            } else {
                pagerState.animateScrollToPage(selectedDayIndex)
            }
        }
        lastPositionedDate = targetDate
    }
    // Surfaced through the same small top-right confirmation used for
    // toggle actions elsewhere on this screen, rather than a second overlay
    // mechanism - a failed/empty jump is the same kind of transient,
    // non-blocking notice.
    LaunchedEffect(jumpToNextGameError) {
        if (jumpToNextGameError != null) {
            actionLabel = jumpToNextGameError
            onJumpToNextGameErrorShown()
        }
    }

    Scaffold(
        containerColor = BackgroundBase,
        topBar = {
            AppTopBar(
                leading = {
                    TitleLeagueSelector(
                        selectedLeague = selectedLeague,
                        onLeagueSelected = onLeagueSelected,
                        enabledLeagues = enabledLeagues,
                        isAllLeaguesSelected = isAllLeaguesSelected,
                        onAllLeaguesSelected = onToggleAllLeagues
                    )
                },
                actions = {
                    // Only shown once the viewer has actually wandered off
                    // today's tab (by swiping or via "jump to next game") -
                    // same "only surface it when it'd do something" rule as
                    // the empty-day jump button, rather than a permanently
                    // present icon that's a no-op most of the time.
                    if (days.getOrNull(selectedDayIndex)?.date != today) {
                        IconButton(onClick = onJumpToToday, enabled = !isJumpingToToday) {
                            if (isJumpingToToday) {
                                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                            } else {
                                Icon(
                                    imageVector = Icons.Default.Today,
                                    contentDescription = "Back to today",
                                    tint = TextSecondary
                                )
                            }
                        }
                    }
                    // Always available now - the calendar scrolls freely
                    // across years and shows real per-day game counts
                    // (fetched lazily per visible month), so it's useful
                    // regardless of whether "the current season" happens to
                    // be loaded for whichever league is selected.
                    IconButton(onClick = { showCalendar = true }, enabled = !isJumpingToDate) {
                        if (isJumpingToDate) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(
                                imageVector = Icons.Default.CalendarMonth,
                                contentDescription = "Jump to date",
                                tint = TextSecondary
                            )
                        }
                    }
                    SortMenuButton(
                        selected = sortOption,
                        onSelected = { sortOption = it },
                        ratingSortEnabled = currentDayHasRatedGame
                    )
                    NumericScoreToggleButton(
                        checked = showNumericScore,
                        onCheckedChange = { onToggleNumericScore() },
                        enabled = currentDayHasRatedGame
                    )
                },
                secondary = {
                    CenteringDayTabRow(
                        days = days,
                        today = today,
                        selectedDayIndex = selectedDayIndex,
                        onDaySelected = onDaySelected
                    )
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
            PullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = onRefresh,
                modifier = Modifier.fillMaxSize()
            ) {
                HorizontalPager(
                    state = pagerState,
                    modifier = Modifier.fillMaxSize()
                ) { page ->
                    // Keyed on the actual DATE being shown at this page
                    // index, not just left to Pager's own default (index-
                    // based) identity - HorizontalPager retains each page
                    // slot's composition (including DayGamesList's own
                    // rememberLazyListState() scroll position) keyed by
                    // index, regardless of what date that index currently
                    // represents. A jump/filter that reshuffles which date
                    // lands on which index (jumpToDateInternal's reload, a
                    // min-tier filter toggle re-deriving orderedGames, or the
                    // narrow-to-full-season swap this same file's pagerState
                    // key() above already guards against for the pager
                    // ITSELF) would otherwise hand the new date's list
                    // whatever scroll offset was left over from a totally
                    // different day at that same index - confirmed live as
                    // the reported bug: the first game tile landing partly
                    // scrolled behind the top bar instead of at the very top.
                    // Keying on the date forces a fresh composition (and so
                    // a fresh, top-of-list listState) any time the date at
                    // this index actually changes.
                    key(days.getOrNull(page)?.date) {
                    Column(modifier = Modifier.fillMaxSize()) {
                        // Only meaningful in "All Leagues" mode - the record
                        // is a cross-league total (see
                        // GameListViewModel.kt's loadYearRecordDaysIfNeeded),
                        // which a single-league view can't show anyway (that
                        // day's single-league count is always a small
                        // fraction of the real combined figure). recordDays
                        // is empty until that background fetch completes, so
                        // this naturally shows nothing while it's loading.
                        if (isAllLeaguesSelected && days[page].date in recordDays) {
                            RecordGameDayBanner(
                                gameCount = days[page].games.size,
                                isTied = recordDays.size > 1,
                                modifier = Modifier.padding(start = 16.dp, top = 8.dp, end = 16.dp)
                            )
                        }
                        DayGamesList(
                            games = days[page].games,
                            sortOption = sortOption,
                            showNumericScore = showNumericScore,
                            nbaWeights = nbaWeights,
                            wnbaWeights = wnbaWeights,
                            mlbWeights = mlbWeights,
                            nflWeights = nflWeights,
                            nhlWeights = nhlWeights,
                            starredIds = starredIds,
                            onToggleStar = onToggleStar,
                            onWatchHighlights = onWatchHighlights,
                            isJumpingToNextGame = isJumpingToNextGame,
                            onJumpToNextGame = onJumpToNextGame,
                            favoriteTeamNames = favoriteTeamNames,
                            bumpFavoriteTeamGames = bumpFavoriteTeamGames,
                            onToggleFavoriteTeam = onToggleFavoriteTeam,
                            favoritePlayerNames = favoritePlayerNames,
                            onToggleFavoritePlayer = onToggleFavoritePlayer,
                            minTierFilterEnabled = minTierFilterEnabled,
                            minTierFilter = minTierFilter,
                            onGameClick = onGameClick,
                            belledGameIds = belledGameIds,
                            onToggleBell = onToggleBell
                        )
                    }
                    }
                }
            }
            ActionLabelOverlay(
                label = actionLabel,
                modifier = Modifier.align(Alignment.TopEnd).padding(top = 4.dp, end = 56.dp)
            )
        }
    }

    if (showCalendar) {
        SeasonCalendarDialog(
            initialMonth = YearMonth.from(today),
            gameCounts = monthCounts,
            gameCountsMonth = monthCountsMonth,
            isLoadingCounts = isLoadingMonthCounts,
            onMonthChanged = onMonthChanged,
            onDateSelected = { date ->
                showCalendar = false
                onJumpToDate(date)
            },
            onDismiss = { showCalendar = false }
        )
    }
}

/**
 * Material3's ScrollableTabRow only scrolls the selected tab into view (edge
 * aligned), not centered — replaced with a manually-scrolled LazyRow of
 * [NavChip]s (the same pill visual every other tab's secondary row uses).
 * Each chip is sized to exactly a third of the viewport (rather than sizing
 * to its own text content), so at rest exactly 3 are ever visible with none
 * peeking in cut off at either edge - scrolling so (selectedDayIndex - 1)
 * becomes the first visible item then reproduces the same "selected chip
 * centered, one neighbor on each side" layout (clamped to the ends of the
 * list, where fewer than one full chip's worth of neighbors exist). Lazy
 * (not a plain Row, unlike [NavChipRow]) since a full WNBA season is ~140
 * days - only NBA's narrow window is small enough that a non-lazy Row
 * would've been fine, but there's no reason to maintain two versions of
 * this centering/sizing behavior just to also use [NavChipRow]'s plain Row.
 */
@Composable
private fun CenteringDayTabRow(
    days: List<DayGames>,
    today: LocalDate,
    selectedDayIndex: Int,
    onDaySelected: (Int) -> Unit
) {
    val listState = rememberLazyListState()
    var viewportWidth by remember { mutableStateOf(0) }
    val density = LocalDensity.current
    val tabWidthPx = viewportWidth / 3

    // Same "don't animate a same-date reindex" guard as DayTabsScreen's own
    // pagerState effect above - the narrow-to-full-season swap moves
    // selectedDayIndex to a different number for the SAME landed-on date
    // (the two windows start on different dates), which would otherwise
    // animate this row a visible distance shortly after the league finishes
    // loading even though nothing the viewer picked has changed.
    var lastPositionedDate by remember { mutableStateOf<LocalDate?>(null) }
    LaunchedEffect(selectedDayIndex, viewportWidth, days) {
        if (tabWidthPx == 0 || days.isEmpty()) return@LaunchedEffect
        val targetIndex = (selectedDayIndex - 1).coerceIn(0, days.size - 1)
        val targetDate = days.getOrNull(selectedDayIndex)?.date
        if (lastPositionedDate == null || targetDate == lastPositionedDate) {
            listState.scrollToItem(targetIndex)
        } else {
            listState.animateScrollToItem(targetIndex)
        }
        lastPositionedDate = targetDate
    }

    LazyRow(
        state = listState,
        modifier = Modifier
            .fillMaxWidth()
            .onSizeChanged { viewportWidth = it.width }
            .padding(vertical = 8.dp)
    ) {
        itemsIndexed(days, key = { _, day -> day.date.toString() }) { index, day ->
            NavChip(
                label = dayTabLabel(day.date, today),
                selected = index == selectedDayIndex,
                onClick = { onDaySelected(index) },
                modifier = Modifier
                    .width(with(density) { tabWidthPx.toDp() })
                    .padding(horizontal = 4.dp)
            )
        }
    }
}

// No best-first sort option here (unlike Starred/History) - every game on
// this tab is already the same single day - most days have only a handful
// of games, but a busy slate (a full WNBA night, or NBA's opening day) can
// have enough that a best-first ordering is genuinely useful, same as
// Starred/History/Favorites' identical 4-option sort.
@Composable
private fun DayGamesList(
    games: List<com.nbawatchability.app.data.Game>,
    sortOption: SortOption,
    showNumericScore: Boolean,
    nbaWeights: RubricWeights,
    wnbaWeights: RubricWeights,
    mlbWeights: MlbRubricWeights,
    nflWeights: NflRubricWeights,
    nhlWeights: NhlRubricWeights,
    starredIds: Set<String>,
    onToggleStar: (com.nbawatchability.app.data.Game) -> Unit,
    onWatchHighlights: (String) -> Unit,
    isJumpingToNextGame: Boolean,
    onJumpToNextGame: () -> Unit,
    favoriteTeamNames: Set<String> = emptySet(),
    bumpFavoriteTeamGames: Boolean = false,
    onToggleFavoriteTeam: (Team) -> Unit = {},
    favoritePlayerNames: Set<String> = emptySet(),
    onToggleFavoritePlayer: (com.nbawatchability.app.data.FavoritePlayer) -> Unit = {},
    minTierFilterEnabled: Boolean = false,
    minTierFilter: Tier = Tier.SKIPPABLE,
    onGameClick: (com.nbawatchability.app.data.Game) -> Unit = {},
    belledGameIds: Set<String> = emptySet(),
    onToggleBell: (com.nbawatchability.app.data.Game) -> Unit = {}
) {
    if (games.isEmpty()) {
        Column(
            modifier = Modifier.fillMaxSize().padding(24.dp),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "No games scheduled",
                color = TextSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth(),
                style = MaterialTheme.typography.titleLarge
            )
            Spacer(modifier = Modifier.height(20.dp))
            // A day with nothing scheduled might just be a quiet gap within
            // an ongoing season, or the tail end of one - either way, rather
            // than making the viewer keep swiping blindly to find out which,
            // this looks ahead (possibly weeks past this window, possibly
            // into a different stage) for whatever the next real game
            // actually is.
            Button(onClick = onJumpToNextGame, enabled = !isJumpingToNextGame) {
                if (isJumpingToNextGame) {
                    CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                } else {
                    Text(text = "Jump to next game")
                }
            }
        }
        return
    }

    // Same unscored-games-fall-back-to-newest-first treatment as every
    // other sortable tab - an upcoming/live game on this same day has no
    // score to sort by yet.
    val orderedGames = when (sortOption) {
        SortOption.RATING_HIGHEST_FIRST -> {
            val (scored, unscored) = games.partition { it.effectiveScore(nbaWeights, wnbaWeights, mlbWeights, nflWeights, nhlWeights) != null }
            scored.sortedByDescending { it.effectiveScore(nbaWeights, wnbaWeights, mlbWeights, nflWeights, nhlWeights) } + unscored.sortedByDescending { it.tipoffUtc }
        }
        SortOption.RATING_LOWEST_FIRST -> {
            val (scored, unscored) = games.partition { it.effectiveScore(nbaWeights, wnbaWeights, mlbWeights, nflWeights, nhlWeights) != null }
            scored.sortedBy { it.effectiveScore(nbaWeights, wnbaWeights, mlbWeights, nflWeights, nhlWeights) } + unscored.sortedByDescending { it.tipoffUtc }
        }
        SortOption.DATE_OLDEST_FIRST -> games.sortedBy { it.tipoffUtc }
        SortOption.DATE_NEWEST_FIRST -> games.sortedByDescending { it.tipoffUtc }
    }.filterByMinTier(minTierFilterEnabled, minTierFilter, nbaWeights, wnbaWeights, mlbWeights, nflWeights, nhlWeights)
        .bumpFavoriteTeamGames(bumpFavoriteTeamGames, favoriteTeamNames)

    val listState = rememberLazyListState()
    // Without this, LazyColumn's key-based item tracking keeps whatever
    // tile was on top in view across a re-sort, same reasoning as every
    // other sortable tab's identical effect. Also keyed on the min-tier
    // filter (minTierFilterEnabled/minTierFilter both feed orderedGames'
    // filterByMinTier call above) - toggling it removes/restores tiles from
    // the SAME day's list without changing which day/page this is, so it
    // needs the same reset-to-top treatment a re-sort gets; previously only
    // sortOption was keyed here, so filtering while scrolled down left the
    // list sitting at whatever index it was, no longer necessarily near the
    // top of the newly-shorter filtered list. Also keyed on
    // bumpFavoriteTeamGames/favoriteTeamNames (the bump reorder, line 560
    // above) - favoriting a team is a long-press directly on one of these
    // same tiles, so with the bump setting on, that gesture reshuffles this
    // very list out from under the viewer without a reset unless it's keyed
    // here too.
    LaunchedEffect(sortOption, minTierFilterEnabled, minTierFilter, bumpFavoriteTeamGames, favoriteTeamNames) {
        listState.animateScrollToTopAdaptively()
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        state = listState,
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        items(orderedGames, key = { it.id }) { game ->
            GameCard(
                game = game,
                showNumericScore = showNumericScore,
                nbaWeights = nbaWeights,
                wnbaWeights = wnbaWeights,
                mlbWeights = mlbWeights,
                nflWeights = nflWeights,
                nhlWeights = nhlWeights,
                isStarred = starredIds.contains(game.id),
                onToggleStar = { onToggleStar(game) },
                showBell = true,
                isBelled = game.eventId != null && belledGameIds.contains(game.eventId),
                onToggleBell = { onToggleBell(game) },
                onWatchHighlights = onWatchHighlights,
                favoriteTeamNames = favoriteTeamNames,
                onToggleFavoriteTeam = onToggleFavoriteTeam,
                favoritePlayerNames = favoritePlayerNames,
                onToggleFavoritePlayer = onToggleFavoritePlayer,
                onGameClick = onGameClick
            )
        }
    }
}
