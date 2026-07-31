package com.nbawatchability.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nbawatchability.app.data.FavoritePlayer
import com.nbawatchability.app.data.Game
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
import com.nbawatchability.app.ui.theme.TextPrimary
import com.nbawatchability.app.ui.theme.TextSecondary
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter

private val earliestDateFormatter = DateTimeFormatter.ofPattern("MMM d, yyyy")

// "All time" holds itself to a much higher bar than every other range - the
// server's own >=70 (gameStore.ts's HISTORY_MIN_SCORE) makes sense across a
// single season, but scanning the *entire* backfill at that same bar would
// surface a long list that isn't really "the best of all time" anymore.
// Applied client-side (not a backend param) since effective score depends
// on the viewer's own rubric weights, same as the existing rating sort
// below - the server's >=70 games are still fetched, this just narrows the
// display further for this one preset.
//
// WNBA gets its own, lower bar - NBA's 90 represents its rarest ~0.1% of
// games (3 of 2,650 in the backfill), but WNBA's entire History-qualifying
// pool (>=70) is only 8 games total, topping out at 81 - applying NBA's
// literal threshold, or even matching NBA's rarity percentile, leaves
// All-time permanently empty (or down to a single game) for WNBA. 75 keeps
// the top 5 of those 8 - still a real cut from "everything," just not one
// calibrated to a sample size WNBA's backfill doesn't have yet. Revisit as
// more WNBA seasons get backfilled and the pool grows past single digits.
private const val ALL_TIME_MIN_SCORE_NBA = 90
private const val ALL_TIME_MIN_SCORE_WNBA = 75
// Revised 2026-07-31 once the full 21-season historical backfill (2003-2023,
// backfillRawStatsMlbHistorical.ts) landed: 80 against the complete
// 55,247-game real dataset (2003-2025) surfaced 63 games - far more than
// NBA's All-time list (7 games) reads as. Bumped to 90, which the same full
// dataset shows clears to exactly 9 games - much closer to NBA's own count
// and a genuinely elite bar again (~0.016% of all real MLB games since
// 2003). James's explicit call, 2026-07-31 - supersedes the original 80
// pick from 2026-07-30, which was only checked against the 2024+2025
// sample (4,951 games) before the older seasons were backfilled.
private const val ALL_TIME_MIN_SCORE_MLB = 90

// Random pick shown when a preset/date range has nothing qualifying - one of
// several instead of always the same sentence, purely for flavor. Overridden
// for "This season" on NBA/NHL/MLB by thisSeasonStartMessage below, whenever
// that's empty specifically because the next season just hasn't started yet
// (the joke lines read as unhelpful noise in that exact situation - the real
// answer is "it hasn't started," not "nothing good happened").
private val EMPTY_HISTORY_LINES = listOf(
    "No barn burners in this range",
    "Nothing but duds as far as the eye can see",
    "Crickets. Not even the good kind",
    "This range is drier than a preseason box score",
    "Zero certified bangers found here",
    "Not a single classic hiding in here",
    "This stretch is criminally boring"
)

// Real, known start dates for each league's *next* season, shown only on
// "This season" when it's empty (i.e. currently in the gap between one
// season ending and the next beginning) - NBA, NHL, and NFL specifically
// (not MLB/WNBA, per James's ask). Regular-season/preseason dates below are
// each league's own official announcement as of 2026-07-28, except NBA's
// preseason (not yet released as of this writing - phrased as "early
// October" rather than a specific day for that reason). These are real
// dates, not placeholders - update them once each league announces its
// following season, the same way backfillRawStatsNfl2024.ts/
// backfillRawStatsNhl2024.ts's own SEASON_WINDOW constants need a fresh
// value every year rather than being computed.
private fun thisSeasonStartMessage(league: LeagueGroup): String? = when (league) {
    LeagueGroup.NBA -> "The next NBA season hasn't tipped off yet - preseason games start in early October, with the regular season opening October 20, 2026."
    LeagueGroup.NHL -> "The next NHL season hasn't dropped the puck yet - preseason starts September 19, with the regular season opening September 29, 2026."
    LeagueGroup.NFL -> "The next NFL season hasn't kicked off yet - preseason begins August 6 with the Hall of Fame Game, and the regular season opens September 9, 2026."
    else -> null
}

/**
 * "Which old games are actually worth going back to watch" - surfaces the
 * per-league watchability backfill (NBA and WNBA both have one, each scored
 * through the same league-aware rubric), games scoring 70+ only
 * (gameStore.ts's HISTORY_MIN_SCORE - stricter than the "Worth Your Time"
 * tier badge's own >=65), most-watchable-first by default - except "All
 * time" (ALL_TIME_MIN_SCORE_NBA/ALL_TIME_MIN_SCORE_WNBA/ALL_TIME_MIN_SCORE_MLB
 * above), which holds every season's worth of backfill to a much higher,
 * per-league bar instead. NFL/NHL don't have their own bar yet and still
 * fall through to NBA's 90 (the `else` branch below) - not yet calibrated
 * against either league's own real score distribution. The breakdown defaults to spoiler-blurred here (GameCard's
 * spoilerFree = false) same as every other tab, tap-to-reveal per game
 * (FullBreakdownSection's own `revealed` state) - was briefly spoilerFree =
 * true on the reasoning that these are old, already-decided games with
 * nothing left to spoil, but that fought the tab's own "browse blind"
 * default (showScore below): revealing comeback size/OT on sight while
 * scores stay hidden was a mixed signal, not a real distinction a user
 * browsing this tab cares about.
 * [showScore] is a separate, purely local "browse blind" preference -
 * unlike spoilerFree, turning it off only hides the two teams' final
 * numeric score digits (tier badge and final result stay visible either
 * way; the breakdown's own visibility is spoilerFree's job, not this
 * one's). Resets to [showScoresByDefault] every time this
 * screen is (re)composed - e.g. navigating back to History from another
 * tab - rather than remembering whatever the toggle was last left at
 * within a single session, so an accidental peek doesn't linger past a
 * tab switch. [showScoresByDefault] itself is a persisted Settings choice
 * (default false, i.e. spoiler-safe), not a session toggle - a user who's
 * decided they don't mind seeing scores can make that the starting state
 * instead of hidden.
 *
 * No hook/pitch preview text is generated or shown here (unlike the
 * pregame preview on other tabs) - these are already-finished games, so
 * there's nothing to preview, and historyService.ts never calls the LLM for
 * them at all.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(
    uiState: HistoryUiState,
    presets: List<HistoryRangePreset>,
    selectedPreset: HistoryRangePreset,
    earliestDate: java.time.LocalDate?,
    onPresetSelected: (HistoryRangePreset) -> Unit,
    onRetry: () -> Unit,
    showNumericScore: Boolean,
    onToggleNumericScore: () -> Unit,
    nbaWeights: RubricWeights,
    wnbaWeights: RubricWeights,
    mlbWeights: MlbRubricWeights,
    nflWeights: NflRubricWeights,
    nhlWeights: NhlRubricWeights,
    starredIds: Set<String>,
    onToggleStar: (Game) -> Unit,
    onWatchHighlights: (String) -> Unit,
    selectedLeague: LeagueGroup,
    onLeagueSelected: (LeagueGroup) -> Unit,
    enabledLeagues: Set<LeagueGroup>,
    isAllLeaguesSelected: Boolean,
    onToggleAllLeagues: () -> Unit,
    favoriteTeamNames: Set<String> = emptySet(),
    bumpFavoriteTeamGames: Boolean = false,
    onToggleFavoriteTeam: (Team) -> Unit = {},
    favoritePlayerNames: Set<String> = emptySet(),
    onToggleFavoritePlayer: (FavoritePlayer) -> Unit = {},
    minTierFilterEnabled: Boolean = false,
    minTierFilter: Tier = Tier.SKIPPABLE,
    showScoresByDefault: Boolean = false,
    onGameClick: (Game) -> Unit = {},
    onPrefetch: (HistoryRangePreset) -> Unit = {},
    belledGameIds: Set<String> = emptySet(),
    onToggleBell: (Game) -> Unit = {},
    // The "Add highlights link" tile affordance (AddHighlightLinkRow in
    // GameCard) - reuses AdminViewModel's own login/token state (same PIN as
    // the hidden Admin page) rather than a separate auth flow, so unlocking
    // here also unlocks Admin proper and vice versa. onAddHighlightLink's
    // callback shape mirrors AdminViewModel.submitManualHighlightFromHistory
    // exactly - AddHighlightLinkDialog is the only thing that calls it.
    isAdminLoggedIn: Boolean = false,
    isAdminLoggingIn: Boolean = false,
    adminLoginError: String? = null,
    onSubmitAdminPin: (String) -> Unit = {},
    onAddHighlightLink: (eventId: String, url: String, onSuccess: (String) -> Unit, onError: (String) -> Unit) -> Unit = { _, _, _, _ -> },
    onHighlightLinkAdded: (eventId: String, videoId: String) -> Unit = { _, _ -> }
) {
    // Plain remember (not rememberSaveable) - resets to showScoresByDefault
    // every time this composable enters composition, e.g. switching back to
    // History from another tab, so a "showing scores" choice never survives
    // a tab switch and can't accidentally spoil something beyond what the
    // user's own persisted default already allows.
    var showScore by remember { mutableStateOf(showScoresByDefault) }
    // A single 4-option sort dropdown (SortMenuButton) rather than two
    // independent toggles - defaults to highest-rated first, matching this
    // tab's own "most watchable first" framing.
    var sortOption by rememberSaveable { mutableStateOf(SortOption.RATING_HIGHEST_FIRST) }
    var actionLabel by remember { mutableStateOf<String?>(null) }
    // Which game's "Add highlights link" dialog is open, if any - plain
    // remember (not rememberSaveable), same reasoning as showScore above:
    // an in-progress paste is fine to lose on a config change/tab switch,
    // it's not meant to survive one.
    var pendingHighlightEventId by remember { mutableStateOf<String?>(null) }

    // Same settledPage/selectedPreset two-way sync as DayTabsScreen's day
    // pager - settledPage (not currentPage) drives the push-to-caller side
    // so an in-flight programmatic jump (e.g. tapping a non-adjacent chip)
    // doesn't re-trigger onPresetSelected for every transient page it
    // crosses, only the one it actually lands on. Unlike DayTabsScreen (or
    // Leaders/Favorites' pagers), each preset's games aren't pre-fetched by
    // default - History only ever shows one preset's data at a time, so
    // every page in this pager renders the same current [uiState] rather
    // than its own distinct slice; the pager here is purely the
    // swipe-gesture/tab-sync layer over the ViewModel's own
    // cache/in-flight-request bookkeeping (HistoryViewModel.fetch), not a
    // second copy of it.
    val pagerState = rememberPagerState(initialPage = presets.indexOf(selectedPreset).coerceAtLeast(0)) { presets.size }
    LaunchedEffect(pagerState.settledPage, presets) {
        val target = presets.getOrNull(pagerState.settledPage)
        if (target != null && target != selectedPreset) onPresetSelected(target)
    }
    LaunchedEffect(selectedPreset, presets) {
        val targetIndex = presets.indexOf(selectedPreset)
        if (targetIndex >= 0 && pagerState.currentPage != targetIndex) {
            pagerState.animateScrollToPage(targetIndex)
        }
    }
    // Warms both neighbors of whichever page is currently front-most -
    // currentPage (not settledPage) so this starts as soon as a swipe
    // begins moving toward a neighbor, not only once it fully settles there,
    // and also fires once up front for the initial page's neighbors while
    // the user is simply sitting on the first page. onPrefetch itself is a
    // no-op for a preset that's already cached or already being fetched
    // (HistoryViewModel.fetch's own guard), so calling this liberally on
    // every currentPage/presets change is cheap.
    LaunchedEffect(pagerState.currentPage, presets) {
        presets.getOrNull(pagerState.currentPage - 1)?.let(onPrefetch)
        presets.getOrNull(pagerState.currentPage + 1)?.let(onPrefetch)
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
                    SortMenuButton(
                        selected = sortOption,
                        onSelected = { sortOption = it }
                    )
                    HideScoresToggleButton(
                        checked = showScore,
                        onCheckedChange = {
                            showScore = it
                            actionLabel = if (it) "Showing scores" else "Hiding scores"
                        }
                    )
                    NumericScoreToggleButton(
                        checked = showNumericScore,
                        onCheckedChange = { onToggleNumericScore() }
                    )
                },
                secondary = {
                    NavChipRow(
                        items = presets,
                        selected = selectedPreset,
                        onSelected = onPresetSelected,
                        label = { it.label }
                    )
                }
            )
        }
    ) { padding ->
        Box(modifier = Modifier.fillMaxSize().padding(padding)) {
        Column(modifier = Modifier.fillMaxSize()) {
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.fillMaxSize()
            ) {
            when (uiState) {
                is HistoryUiState.Loading -> Column(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    CircularProgressIndicator()
                }

                is HistoryUiState.Error -> Column(
                    modifier = Modifier.fillMaxSize().padding(24.dp),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    Text(
                        text = "Couldn't load history",
                        color = TextPrimary,
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = uiState.message,
                        color = TextSecondary,
                        style = MaterialTheme.typography.bodyMedium,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = 8.dp, bottom = 16.dp)
                    )
                    Button(onClick = onRetry) { Text("Retry") }
                }

                is HistoryUiState.Loaded -> {
                    // Looked up per-game (leagueGroupOf(it), not the single
                    // selectedLeague dropdown value) - correct in both
                    // single-league mode (every game already belongs to
                    // selectedLeague, so this is a no-op change there) and
                    // "All Leagues" mode, where a merged list can hold games
                    // from more than one league at once, each needing its
                    // own bar.
                    val displayGames = if (selectedPreset is HistoryRangePreset.AllTime) {
                        uiState.games.filter { game ->
                            val allTimeMinScore = when (leagueGroupOf(game)) {
                                LeagueGroup.WNBA -> ALL_TIME_MIN_SCORE_WNBA
                                LeagueGroup.MLB -> ALL_TIME_MIN_SCORE_MLB
                                else -> ALL_TIME_MIN_SCORE_NBA
                            }
                            (game.effectiveScore(nbaWeights, wnbaWeights, mlbWeights, nflWeights, nhlWeights) ?: 0) >= allTimeMinScore
                        }
                    } else {
                        uiState.games
                    }

                    if (displayGames.isEmpty()) {
                        val earliestText = earliestDate?.format(earliestDateFormatter)
                        // Only meaningful for "This season" - a named season or
                        // "All time" being empty has nothing to do with whether
                        // the *next* season has started, so those keep the
                        // plain joke line below regardless of league.
                        val seasonStartMessage = if (selectedPreset is HistoryRangePreset.ThisSeason) {
                            thisSeasonStartMessage(selectedLeague)
                        } else {
                            null
                        }
                        // Re-picked whenever the preset changes (not on every
                        // recomposition) so it doesn't flicker between jokes
                        // while this same empty state stays on screen. Only
                        // actually shown when seasonStartMessage is null.
                        val jokeLine = remember(selectedPreset) { EMPTY_HISTORY_LINES.random() }
                        Column(
                            modifier = Modifier.fillMaxSize(),
                            verticalArrangement = Arrangement.Center
                        ) {
                            Text(
                                text = seasonStartMessage
                                    ?: (jokeLine + (if (earliestText != null) " - data goes back to $earliestText, try a wider one." else ".")),
                                color = TextSecondary,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.fillMaxWidth().padding(24.dp),
                                style = MaterialTheme.typography.titleMedium
                            )
                        }
                    } else {
                        // "All time" only - the single highest-scoring game in
                        // the All-time-qualifying set (displayGames, before
                        // sort/min-tier-filter/favorite-bump reorder it below)
                        // gets the GOAT crown. Any other preset leaves this
                        // null - a "highest of the last 7 days" badge isn't
                        // the same claim as "of all time" and shouldn't wear
                        // the same crown.
                        val goatId = if (selectedPreset is HistoryRangePreset.AllTime) {
                            displayGames.maxByOrNull { it.effectiveScore(nbaWeights, wnbaWeights, mlbWeights, nflWeights, nhlWeights) ?: -1 }?.id
                        } else {
                            null
                        }
                        // Ordered by the user's own rubric weights (not just
                        // the server's stored score) when sorting by rating -
                        // every History game already has a score, so unlike
                        // Starred there's no unscored tail to fall back to.
                        val ordered = when (sortOption) {
                            SortOption.RATING_HIGHEST_FIRST -> displayGames.sortedByDescending { it.effectiveScore(nbaWeights, wnbaWeights, mlbWeights, nflWeights, nhlWeights) }
                            SortOption.RATING_LOWEST_FIRST -> displayGames.sortedBy { it.effectiveScore(nbaWeights, wnbaWeights, mlbWeights, nflWeights, nhlWeights) }
                            SortOption.DATE_OLDEST_FIRST -> displayGames.sortedBy { OffsetDateTime.parse(it.tipoffUtc) }
                            SortOption.DATE_NEWEST_FIRST -> displayGames.sortedByDescending { OffsetDateTime.parse(it.tipoffUtc) }
                        }.filterByMinTier(minTierFilterEnabled, minTierFilter, nbaWeights, wnbaWeights, mlbWeights, nflWeights, nhlWeights)
                            .bumpFavoriteTeamGames(bumpFavoriteTeamGames, favoriteTeamNames)

                        val listState = rememberLazyListState()
                        // Without this, LazyColumn's key-based item tracking
                        // keeps whatever tile was on top in view across a
                        // re-sort (since it's usually still in the new list,
                        // just at a different index) - which can make an
                        // already-correct sort look wrong, not just skip the
                        // scroll-to-top animation.
                        LaunchedEffect(sortOption) { listState.animateScrollToTopAdaptively() }

                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            state = listState,
                            contentPadding = PaddingValues(16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            items(ordered, key = { it.id }) { game ->
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
                                    onAddHighlightLink = { pendingHighlightEventId = it },
                                    showDate = true,
                                    spoilerFree = false,
                                    showScore = showScore,
                                    favoriteTeamNames = favoriteTeamNames,
                                    onToggleFavoriteTeam = onToggleFavoriteTeam,
                                    favoritePlayerNames = favoritePlayerNames,
                                    onToggleFavoritePlayer = onToggleFavoritePlayer,
                                    onGameClick = onGameClick,
                                    isGoat = game.id == goatId
                                )
                            }
                        }
                    }
                }
            }
            }
        }
        ActionLabelOverlay(
            label = actionLabel,
            modifier = Modifier.align(Alignment.TopEnd).padding(top = 4.dp, end = 4.dp)
        )
        val pendingId = pendingHighlightEventId
        if (pendingId != null) {
            AddHighlightLinkDialog(
                isLoggedIn = isAdminLoggedIn,
                isLoggingIn = isAdminLoggingIn,
                loginError = adminLoginError,
                onSubmitPin = onSubmitAdminPin,
                onSubmitLink = { url, onSuccess, onError -> onAddHighlightLink(pendingId, url, onSuccess, onError) },
                onLinkSaved = { videoId ->
                    onHighlightLinkAdded(pendingId, videoId)
                    actionLabel = "Highlights link added"
                    pendingHighlightEventId = null
                },
                onDismiss = { pendingHighlightEventId = null }
            )
        }
        }
    }
}
