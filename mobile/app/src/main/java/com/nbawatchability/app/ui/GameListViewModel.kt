package com.nbawatchability.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nbawatchability.app.data.BACKEND_BASE_URL
import com.nbawatchability.app.data.DayGames
import com.nbawatchability.app.data.Game
import com.nbawatchability.app.data.LeagueGroup
import com.nbawatchability.app.data.NetworkGameRepository
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.YearMonth
import java.time.ZoneId

sealed interface ScheduleUiState {
    data object Loading : ScheduleUiState
    data class Error(val message: String) : ScheduleUiState
    data class Loaded(val days: List<DayGames>) : ScheduleUiState
}

private const val DISPLAY_RANGE_DAYS = 7L

// The backend buckets each game under whichever date its scoreboard fetch
// used (ESPN's own US-Eastern-based scoreboard day), not the viewer's local
// calendar date. For anyone outside the Americas that's routinely off by a
// day, so this queries a couple of days of buffer beyond what's displayed
// and re-buckets every game itself by the local date its tipoff actually
// falls on, before slicing back down to the requested display window.
private const val QUERY_BUFFER_DAYS = 2L

// The backend's own abuse guard on /schedule (httpHandler.ts's
// MAX_RANGE_DAYS) - a full-season fetch (seasonRange below) has to be split
// into chunks no wider than this and merged, rather than requested in one
// call. The fixed +/-DISPLAY_RANGE_DAYS fallback window already fits in a
// single chunk, so this only ever actually splits anything for a league
// with a full season range loaded.
private const val MAX_FETCH_CHUNK_DAYS = 21L

// How long a same-session league switch-back can reuse the in-memory
// scheduleCache before treating it as stale and re-fetching - long enough
// that rapid tab-flipping (checking a couple of leagues, coming back) feels
// instant, short enough that a live game's score/status can't go more than
// a minute out of date if the user lands back on it. Games/Starred's own
// ON_RESUME refresh already covers the currently-viewed league; this only
// governs a league the user switched AWAY from and back TO.
private const val SWITCH_CACHE_TTL_MS = 60_000L

private fun cacheKeyFor(leagueGroups: List<LeagueGroup>): String =
    leagueGroups.map { it.apiValue }.sorted().joinToString(",")

class GameListViewModel : ViewModel() {

    val today: LocalDate = LocalDate.now()

    var uiState by mutableStateOf<ScheduleUiState>(ScheduleUiState.Loading)
        private set

    // Pull-to-refresh spinner for re-fetching on top of already-loaded data.
    // Kept separate from uiState so a refresh failure doesn't blow away what's
    // already on screen - it just stops spinning and leaves the old data.
    var isRefreshing by mutableStateOf(false)
        private set

    var selectedDayIndex by mutableStateOf(0)
        private set

    // Incremented on every load() call - the two-phase fetch inside load()
    // (fast narrow window first, full season second) checks its own
    // captured token against this before each uiState write, so a slow
    // background second-phase fetch for a league the user has since
    // switched AWAY from can never overwrite what a newer load() already
    // painted. Plain Int, not thread-safety-sensitive - both the write
    // here and the reads inside load() happen on the same
    // Dispatchers.Main.immediate viewModelScope.
    private var loadToken = 0

    // Which league(s)' slate is currently loaded - set by load(), reused by
    // refresh()/fetchGamesForLocalDate() so callers don't need to keep
    // threading it through on every pull-to-refresh. More than one entry
    // only when the "All Leagues" dropdown option is active (AppRoot.kt's
    // GamesTab) - each league is fetched/chunked independently and merged,
    // see fetchScheduleChunked below.
    private var currentLeagueGroups: List<LeagueGroup> = listOf(LeagueGroup.NBA)

    // Public read-only view of the above - lets a caller (AppRoot's GamesTab)
    // tell whether [uiState] actually reflects the league(s) it's currently
    // asking for, or is still leftover from whatever this ViewModel-instance
    // (Activity-scoped, so it outlives switching away from and back to the
    // Games tab) last had loaded before its LaunchedEffect(selectedLeague) had
    // a chance to fire. Without this check, a league switch made from another
    // tab (e.g. Favorites) - then tapping into Games - renders one stale frame
    // of the OLD league's schedule before load()'s coroutine catches up,
    // because reading [uiState] during composition happens synchronously but
    // LaunchedEffect's call to load() is scheduled a frame later.
    val loadedForLeagueGroups: List<LeagueGroup> get() = currentLeagueGroups

    // Center of the currently-loaded +/-7 day window - only used when
    // [seasonRange] is null. Starts at "today" but moves when jumpToDate()
    // re-centers the window on a date outside the previously-loaded range.
    // Kept separate from [today] itself, which stays the real device date
    // for "Yesterday"/"Today"/"Tomorrow" labeling regardless of where the
    // window is currently centered.
    private var windowCenter: LocalDate = today

    // In-memory, per-ViewModel-instance cache of a full fetchSchedule() result,
    // keyed by the exact leagueGroups list this tab was loaded with - lets
    // switching away to a different league and back within the same session
    // skip the network entirely instead of re-running the whole
    // seasonWindow+chunked-fetch pipeline again. Bounded by
    // SWITCH_CACHE_TTL_MS rather than kept forever: a league with a live
    // game in progress needs a switch-back to still pick up real score/
    // status changes reasonably soon, not show an arbitrarily stale
    // snapshot from earlier in the session. Deliberately NOT persisted
    // across process death/ViewModel recreation - this is purely a same-
    // session "don't redo work you just did" cache, not a replacement for
    // the backend's own longer-lived per-date cache (httpHandler.ts's
    // scheduleDay cache), which is what actually saves real ESPN-fetch
    // work on a cold switch.
    private val scheduleCache = mutableMapOf<String, CachedSchedule>()

    private data class CachedSchedule(
        val fetchedAtMs: Long,
        val days: List<DayGames>,
        val seasonRange: Pair<LocalDate, LocalDate>?
    )

    // The real start-of-season through latest-known-date range, whenever the
    // backend can derive one - null falls back to the fixed
    // +/-DISPLAY_RANGE_DAYS window above. Fetched once per load() for every
    // league (not gated to a specific one - this is meant to be the standard
    // schedule-navigation pattern for any league's Games tab, current or
    // future), not re-queried on every jump (the backend itself caches it
    // once a day, so there's little to gain from asking again more often
    // within a session). NetworkGameRepository.seasonWindow already returns
    // null (not a thrown error) whenever the backend can't derive a window
    // yet, so calling this unconditionally is safe even for a league ESPN
    // doesn't have enough schedule data for right now.
    private var seasonRange by mutableStateOf<Pair<LocalDate, LocalDate>?>(null)

    /**
     * Null until a full-season range loads for the current league - this
     * still only exists to let fetchSchedule() below eagerly load the whole
     * season's day-tabs instead of a narrow +/-7 day window (WNBA/MLB/NFL/
     * NHL/NBA all get this once their own season is real and current). It no
     * longer gates the calendar-picker button itself - that's always shown
     * now (see monthCounts below), since the calendar works for any month of
     * any year regardless of whether a "current season" is loaded.
     */
    val fullSeasonRange: Pair<LocalDate, LocalDate>? get() = seasonRange

    // Counts for whichever single month the calendar dialog currently has
    // open - fetched lazily per visible month (loadMonthCounts below) rather
    // than for the whole year up front, since the backend's own
    // scheduleCountsService.ts is deliberately cheap per month but there's
    // still no reason to fetch months nobody's scrolled to yet. Keyed by the
    // month itself (not just a flat date set) so a stale response from a
    // month the user has since scrolled away from can be told apart from
    // "this month's real counts, still loading."
    var monthCounts by mutableStateOf<Map<LocalDate, Int>>(emptyMap())
        private set
    var monthCountsMonth by mutableStateOf<YearMonth?>(null)
        private set
    var isLoadingMonthCounts by mutableStateOf(false)
        private set

    /**
     * Fetches real per-day game counts for [month] across every league in
     * [leagueGroups] (more than one only in "All Leagues" mode - each
     * league's counts are fetched in parallel and summed per date, same
     * "merge independently" shape as FavoriteGamesViewModel's per-team
     * fetches). Safe to call again for the same month that's already loaded
     * (e.g. the calendar re-opening) - cheap since the backend caches each
     * (league, year, month) once per day itself.
     */
    fun loadMonthCounts(month: YearMonth, leagueGroups: List<LeagueGroup>) {
        isLoadingMonthCounts = true
        viewModelScope.launch {
            try {
                val perLeague = leagueGroups.map { leagueGroup ->
                    async {
                        runCatching {
                            NetworkGameRepository.scheduleCounts(BACKEND_BASE_URL, month.year, month.monthValue, leagueGroup)
                        }.getOrDefault(emptyMap())
                    }
                }.awaitAll()

                val merged = mutableMapOf<LocalDate, Int>()
                for (counts in perLeague) {
                    for ((date, count) in counts) {
                        merged[date] = (merged[date] ?: 0) + count
                    }
                }
                monthCounts = merged
                monthCountsMonth = month
            } catch (e: Exception) {
                // Leave whatever was already loaded (likely the previous
                // month) rather than blanking the calendar over one failed
                // fetch - same "don't discard good state over a transient
                // error" reasoning as refresh() above.
            } finally {
                isLoadingMonthCounts = false
            }
        }
    }

    // The real busiest local calendar day(s) of [recordDaysYear] across every
    // league in [recordDaysLeagueGroups] combined - computed dynamically
    // (not a hardcoded date), by fetching all 12 months' real per-day counts
    // the same way loadMonthCounts does and finding whichever date(s) tie for
    // the year's real maximum. More than one date is common, not an edge
    // case to special-case away - a shared max naturally ties across several
    // real dates in a given year (2026, at the time this was built, actually
    // ties across three: 2026-03-28, 2026-04-07, and 2026-04-12, all at the
    // same combined total in Eastern-day terms - though which specific local
    // date(s) a given viewer's own device lands on can shift by a day either
    // way once bucketed to their own timezone, same reasoning as
    // loadMonthCounts/scheduleCounts). Every one of them gets the banner, not
    // just one arbitrarily picked "the" record day.
    var recordDays by mutableStateOf<Set<LocalDate>>(emptySet())
        private set
    var recordDayGameCount by mutableStateOf(0)
        private set
    var isLoadingRecordDays by mutableStateOf(false)
        private set
    private var recordDaysLoadedFor: Pair<Int, List<LeagueGroup>>? = null

    /**
     * Fetches (once per real year+league-set combo, cached thereafter for
     * the session - see [recordDaysLoadedFor]) every month's real per-day
     * counts for [year] across [leagueGroups] and records whichever date(s)
     * tie for the highest combined total. Safe to call on every
     * composition; only actually fetches again if [year] or [leagueGroups]
     * changed since the last successful load.
     */
    fun loadYearRecordDaysIfNeeded(year: Int, leagueGroups: List<LeagueGroup>) {
        val key = year to leagueGroups
        if (recordDaysLoadedFor == key || isLoadingRecordDays) return

        isLoadingRecordDays = true
        viewModelScope.launch {
            try {
                // Per league, not flattened across (month, league) pairs -
                // each month's own request already includes a 1-day buffer
                // either side (scheduleCountsService.ts) for boundary-
                // shifting games, so consecutive months' requests overlap by
                // one real date (e.g. both March's and April's own fetch
                // include April 1). Merging those 12 months with addition
                // would double-count every boundary date's games - this
                // merges within one league's 12 months with plain
                // assignment instead (last write wins, not a running sum),
                // since an overlapping date's count is identical no matter
                // which of the two adjacent months' responses it came from.
                // Only the merge ACROSS leagues below is a real sum, since
                // different leagues' games on the same date are genuinely
                // additional, not overlapping duplicates of each other.
                val perLeagueTotals = leagueGroups.map { leagueGroup ->
                    async {
                        val monthResults = (1..12).map { month ->
                            async {
                                runCatching {
                                    NetworkGameRepository.scheduleCounts(BACKEND_BASE_URL, year, month, leagueGroup)
                                }.getOrDefault(emptyMap())
                            }
                        }.awaitAll()

                        val leagueTotals = mutableMapOf<LocalDate, Int>()
                        for (monthCounts in monthResults) {
                            for ((date, count) in monthCounts) {
                                // Guards against a buffer day spilling into
                                // the adjacent calendar year too (e.g.
                                // January's request pulling in December 31
                                // of the year before).
                                if (date.year == year) leagueTotals[date] = count
                            }
                        }
                        leagueTotals
                    }
                }.awaitAll()

                val totals = mutableMapOf<LocalDate, Int>()
                for (leagueTotals in perLeagueTotals) {
                    for ((date, count) in leagueTotals) {
                        totals[date] = (totals[date] ?: 0) + count
                    }
                }

                val max = totals.values.maxOrNull() ?: 0
                recordDayGameCount = max
                recordDays = if (max > 0) totals.filterValues { it == max }.keys else emptySet()
                recordDaysLoadedFor = key
            } catch (e: Exception) {
                // Leave whatever was already found (or the empty initial
                // state) rather than erroring the whole Games tab over a
                // background easter-egg computation.
            } finally {
                isLoadingRecordDays = false
            }
        }
    }

    /**
     * Full reload for [leagueGroups] - called on first composition and
     * again whenever the league selection changes (a single-element list
     * for a normal league pick, more than one when "All Leagues" is
     * active). The season-range/calendar-picker fast path (below) only
     * applies to a single league - merging multiple leagues' own season
     * ranges isn't well-defined, so multi-league mode always falls back to
     * the fixed +/-[DISPLAY_RANGE_DAYS] window instead.
     */
    fun load(leagueGroups: List<LeagueGroup>) {
        currentLeagueGroups = leagueGroups
        windowCenter = today
        seasonRange = null
        val token = ++loadToken
        uiState = ScheduleUiState.Loading

        val cacheKey = cacheKeyFor(leagueGroups)
        val cached = scheduleCache[cacheKey]
        if (cached != null && System.currentTimeMillis() - cached.fetchedAtMs < SWITCH_CACHE_TTL_MS) {
            com.nbawatchability.app.util.FileLogger.log("PERF", "GameListViewModel.load: same-session cache hit for $cacheKey, skipping network entirely")
            seasonRange = cached.seasonRange
            val cachedLandsOnSeasonStart = cached.seasonRange != null && today !in cached.seasonRange.first..cached.seasonRange.second
            val cachedAnchor = if (cachedLandsOnSeasonStart) cached.seasonRange!!.first else today
            selectedDayIndex = landingIndex(cached.days, cachedAnchor, cachedLandsOnSeasonStart)
            uiState = ScheduleUiState.Loaded(cached.days)
            return
        }

        // Two-phase: a fast narrow window first (paints something on
        // screen in roughly one chunk's worth of latency), then the full
        // season range - if there is one - streams in behind it and
        // replaces the view once ready. Cuts cold time-to-first-paint from
        // "however long the whole multi-chunk season fetch takes" down to
        // "one narrow-window fetch," which is the dominant remaining cold-
        // start cost the server/client caching fixes (P1 follow-up,
        // 2026-07-27) don't address - those only help REPEAT access to
        // already-fetched date ranges, not a genuinely first-ever fetch.
        // [token] guards every uiState/selectedDayIndex write below against
        // a newer load() (the user switched leagues again mid-flight)
        // having already taken over - without it, this phase's slow
        // second-half fetch for the OLD league could land after the new
        // league's own first paint and silently stomp over it.
        viewModelScope.launch {
            val startMs = System.currentTimeMillis()
            com.nbawatchability.app.util.FileLogger.log("PERF", "GameListViewModel.load START for ${leagueGroups.map { it.displayName }}")
            try {
                val seasonStart = System.currentTimeMillis()
                val range = leagueGroups.singleOrNull()?.let { NetworkGameRepository.seasonWindow(BACKEND_BASE_URL, it) }
                if (token != loadToken) return@launch
                seasonRange = range
                com.nbawatchability.app.util.FileLogger.log("PERF", "seasonWindow took ${System.currentTimeMillis() - seasonStart}ms")

                // Anchored on today if today actually falls within the real
                // season (the common case - a season currently in
                // progress), otherwise on the season's own start date -
                // matching where selectedDayIndex's own
                // indexOfFirst{...}.coerceAtLeast(0) fallback would land
                // anyway (e.g. NHL in its summer off-season: today isn't in
                // range, so the meaningful "first paint" is the season
                // opener, not an empty today-centered window nobody would
                // look at before it gets replaced a moment later).
                //
                // range.first/range.second are the backend's raw ESPN
                // calendar-day boundaries (Eastern/UTC-ish, see
                // seasonWindowService.ts), NOT local-date-bucketed the way
                // the actual displayed days are (rebucketByLocalDate below
                // re-buckets every game by the VIEWER's local tipoff date).
                // For anyone in a timezone ahead of the Americas, the real
                // season-opener game's local date lands one day AFTER this
                // raw anchor string - landsOnSeasonStart below tracks
                // whether we're in this "not currently in season" case so
                // landingIndex can prefer whichever day in the loaded window
                // actually has games instead of trusting this raw string
                // literally (confirmed live: NFL's 2026 preseason boundary
                // is "2026-08-06T07:00Z", sliced to "2026-08-06", while the
                // real Hall of Fame Game's evening-ET kickoff falls on
                // Aug 7 local for anyone at UTC-4 or later).
                val landsOnSeasonStart = range != null && today !in range.first..range.second
                val anchor = if (landsOnSeasonStart) range!!.first else today
                val narrowStart = anchor.minusDays(DISPLAY_RANGE_DAYS)
                val narrowEnd = anchor.plusDays(DISPLAY_RANGE_DAYS)

                val narrowStartMs = System.currentTimeMillis()
                val narrowFetched = fetchScheduleChunked(
                    narrowStart.minusDays(QUERY_BUFFER_DAYS),
                    narrowEnd.plusDays(QUERY_BUFFER_DAYS),
                    leagueGroups
                )
                val narrowDays = rebucketByLocalDate(narrowFetched, narrowStart, narrowEnd)
                com.nbawatchability.app.util.FileLogger.log(
                    "PERF",
                    "narrow window fetch took ${System.currentTimeMillis() - narrowStartMs}ms, got ${narrowDays.size} days"
                )

                if (token != loadToken) return@launch
                selectedDayIndex = landingIndex(narrowDays, anchor, landsOnSeasonStart)
                uiState = ScheduleUiState.Loaded(narrowDays)
                com.nbawatchability.app.util.FileLogger.log("PERF", "GameListViewModel.load FIRST PAINT in ${System.currentTimeMillis() - startMs}ms")

                // Only worth a second, full fetch if the real season
                // actually extends past what the narrow window above
                // already covered - a short season (or no season data at
                // all) means the narrow fetch already has everything.
                //
                // This phase is wrapped in its OWN try/catch, separate from
                // phase 1 above - it's inherently more failure-prone (up to
                // ~10 concurrent chunk requests for a full season, vs. phase
                // 1's single narrow-window request) and phase 1 has ALREADY
                // painted a correct, usable view by this point. Letting a
                // phase-2 failure fall through to the outer catch below
                // would replace that already-good Loaded state with a hard
                // Error screen - confirmed live as the reported bug ("NHL
                // loads on season opener, which is correct, then crashes to
                // couldn't-load-games/internal error"): the narrow window
                // rendered fine, then the full-season fetch hit a transient
                // failure and stomped it. Swallowing it here instead just
                // leaves the narrow window in place - a real but reduced
                // view (no season chips beyond +/-7 days) beats replacing a
                // working screen with an error.
                val needsFullFetch = range != null && (range.first < narrowStart || range.second > narrowEnd)
                val finalDays = if (needsFullFetch) {
                    try {
                        val fullStartMs = System.currentTimeMillis()
                        val fullDays = fetchSchedule()
                        com.nbawatchability.app.util.FileLogger.log(
                            "PERF",
                            "full season fetch took ${System.currentTimeMillis() - fullStartMs}ms, got ${fullDays.size} days"
                        )
                        if (token != loadToken) return@launch
                        selectedDayIndex = landingIndex(fullDays, anchor, landsOnSeasonStart)
                        uiState = ScheduleUiState.Loaded(fullDays)
                        fullDays
                    } catch (e: Exception) {
                        com.nbawatchability.app.util.FileLogger.logError("PERF", "GameListViewModel.load full-season fetch failed, keeping narrow window", e)
                        narrowDays
                    }
                } else {
                    narrowDays
                }

                // seasonRange only stored alongside the cache entry when the
                // full fetch actually succeeded (or wasn't needed) - if it
                // failed, finalDays is just the narrow window and doesn't
                // actually cover seasonRange, so caching it under that range
                // would mislead a later cache-hit load() into thinking the
                // full season is already loaded.
                val cachedSeasonRangeForThisLoad = if (finalDays === narrowDays && needsFullFetch) null else seasonRange
                scheduleCache[cacheKey] = CachedSchedule(System.currentTimeMillis(), finalDays, cachedSeasonRangeForThisLoad)
                com.nbawatchability.app.util.FileLogger.log("PERF", "GameListViewModel.load DONE in ${System.currentTimeMillis() - startMs}ms")
            } catch (e: Exception) {
                if (token == loadToken) {
                    com.nbawatchability.app.util.FileLogger.logError("PERF", "GameListViewModel.load ERROR", e)
                    uiState = ScheduleUiState.Error(e.message ?: "Couldn't reach the backend")
                }
            }
        }
    }

    // Separate from uiState/isRefreshing, same reasoning as isRefreshing:
    // a failed jump (or one that finds nothing) shouldn't blow away whatever
    // empty day the user was already looking at.
    var isJumping by mutableStateOf(false)
        private set
    var jumpError by mutableStateOf<String?>(null)
        private set

    fun clearJumpError() {
        jumpError = null
    }

    /**
     * Finds and jumps to the next date (possibly outside the currently
     * loaded window, possibly weeks away) that has a real scheduled game,
     * starting from whichever day is currently being viewed - the empty day
     * the user landed on, not necessarily "today".
     */
    fun jumpToNextGame() {
        if (isJumping) return
        val loadedState = uiState as? ScheduleUiState.Loaded ?: return
        val fromDate = loadedState.days.getOrNull(selectedDayIndex)?.date ?: return

        isJumping = true
        jumpError = null
        viewModelScope.launch {
            try {
                // Nearest next game across every currently-loaded league,
                // not just the first - a multi-league "All Leagues" jump
                // should land on whichever league's next game comes first.
                val nextDate = currentLeagueGroups.mapNotNull { league ->
                    NetworkGameRepository.nextGameDate(baseUrl = BACKEND_BASE_URL, after = fromDate, leagueGroup = league)
                }.minOrNull()
                if (nextDate == null) {
                    jumpError = "No upcoming games found yet"
                } else {
                    jumpToDateInternal(nextDate, loadedState, preferFirstGameOnOrAfter = true) { jumpError = it }
                }
            } catch (e: Exception) {
                jumpError = e.message ?: "Couldn't reach the backend"
            } finally {
                isJumping = false
            }
        }
    }

    // Only meaningful when a jump has to reload the window (the target date
    // fell outside what's currently loaded) - the common case, the date
    // already being in the loaded window, resolves synchronously and never
    // touches this.
    var isJumpingToToday by mutableStateOf(false)
        private set

    /**
     * Jumps straight back to today's tab - instant if today is still within
     * the loaded window (just a selectedDayIndex change), otherwise reloads
     * the window/range to include it.
     */
    fun jumpToToday() {
        if (isJumpingToToday) return
        val loadedState = uiState as? ScheduleUiState.Loaded ?: return
        val existingIndex = loadedState.days.indexOfFirst { it.date == today }
        if (existingIndex >= 0) {
            selectedDayIndex = existingIndex
            return
        }

        isJumpingToToday = true
        viewModelScope.launch {
            try {
                jumpToDateInternal(today, loadedState) { jumpError = it }
            } finally {
                isJumpingToToday = false
            }
        }
    }

    var isJumpingToDate by mutableStateOf(false)
        private set

    /**
     * Jumps to an arbitrary date - backs the calendar picker. With a full
     * season range loaded (WNBA), any in-season date is already present, so
     * this almost always resolves instantly; it only reaches the network
     * for the rare case ESPN has since published dates beyond what was
     * cached at load() time (e.g. playoffs added after the regular season
     * was already loaded).
     */
    fun jumpToDate(date: LocalDate) {
        if (isJumpingToDate) return
        val loadedState = uiState as? ScheduleUiState.Loaded ?: return
        val existingIndex = loadedState.days.indexOfFirst { it.date == date }
        if (existingIndex >= 0) {
            selectedDayIndex = existingIndex
            return
        }

        isJumpingToDate = true
        viewModelScope.launch {
            try {
                jumpToDateInternal(date, loadedState) { jumpError = it }
            } finally {
                isJumpingToDate = false
            }
        }
    }

    private suspend fun jumpToDateInternal(
        date: LocalDate,
        loadedState: ScheduleUiState.Loaded,
        preferFirstGameOnOrAfter: Boolean = false,
        onError: (String) -> Unit
    ) {
        try {
            // seasonRange, once fetched, is fixed for the rest of the
            // session (see its declaration above) and reflects whichever
            // season the backend currently considers "current" for this
            // league - for a league that's off-season, that's the UPCOMING
            // season, not the one just finished. A calendar jump to a date
            // before that (last season, or the off-season gap) falls
            // outside [seasonRange], so blindly re-fetching that same range
            // would come back with the exact same days as before - never
            // containing the requested date, and coercing selectedDayIndex
            // to 0 (the season opener) instead of actually moving. Treated
            // the same as the seasonRange == null case: fall back to a
            // narrow window centered on the requested date instead of the
            // stale season bounds. dateOutsideSeason is also carried into
            // the cache write below so a later cache-hit load() doesn't
            // mistake these narrow-window days for full-season coverage.
            val currentSeasonRange = seasonRange
            val dateOutsideSeason = currentSeasonRange != null &&
                date !in currentSeasonRange.first..currentSeasonRange.second
            if (currentSeasonRange == null || dateOutsideSeason) windowCenter = date
            val days = if (dateOutsideSeason) fetchSchedule(forceNarrowAround = date) else fetchSchedule()
            val cachedSeasonRange = if (dateOutsideSeason) null else seasonRange
            scheduleCache[cacheKeyFor(currentLeagueGroups)] = CachedSchedule(System.currentTimeMillis(), days, cachedSeasonRange)
            // jumpToNextGame's [date] is the backend's raw ESPN scoreboard-
            // day boundary for the next game, not local-date-bucketed the
            // way [days] is (rebucketByLocalDate re-buckets every game by
            // the VIEWER's local tipoff date) - same cross-timezone gap
            // documented on load()'s landsOnSeasonStart above (confirmed
            // live there: NFL's raw boundary "2026-08-06" vs. the real local
            // date "2026-08-07" for anyone at UTC-4 or later). Since [days]
            // always has an entry for every date in the fetched window
            // (empty or not), a plain equality match on the raw [date]
            // "succeeds" by landing on that empty day - one day before the
            // real next game - instead of actually failing over. Bounded to
            // `it.date >= date` (not an unbounded "first day with games
            // anywhere in the window") since the fetched window can span a
            // few days BEFORE [date] too - an unbounded scan there could
            // land on an unrelated earlier game instead of the real next one.
            val firstGameOnOrAfterIndex = if (preferFirstGameOnOrAfter) {
                days.indexOfFirst { it.date >= date && it.games.isNotEmpty() }
            } else {
                -1
            }
            selectedDayIndex = if (firstGameOnOrAfterIndex >= 0) firstGameOnOrAfterIndex else days.indexOfFirst { it.date == date }.coerceAtLeast(0)
            uiState = ScheduleUiState.Loaded(days)
        } catch (e: Exception) {
            onError(e.message ?: "Couldn't reach the backend")
        }
    }

    /**
     * Pull-to-refresh: re-fetches only the currently-viewed day (plus a small
     * buffer so the cross-timezone rebucketing stays correct), not the whole
     * loaded range - there's no reason a refresh of "today" should also
     * re-hit the backend for every other day nobody's looking at. Live
     * games are never cached stale server-side, so this alone is enough to
     * pick up score/period/clock updates for the visible day. Leaves the
     * current view untouched on failure rather than replacing it with an
     * error screen.
     */
    fun refresh() {
        if (isRefreshing) return
        val loadedState = uiState as? ScheduleUiState.Loaded ?: return
        val targetDate = loadedState.days.getOrNull(selectedDayIndex)?.date ?: return
        // Same staleness guard load() uses (see loadToken's own comment) -
        // without this, a refresh() started for the OLD league (fired by
        // GamesTab's LifecycleEventEffect(ON_RESUME), which Android's
        // Lifecycle replays synthetically for every newly-composed observer
        // on an already-resumed Activity - i.e. on every fresh entry into
        // the Schedule tab, not just a real app-background/foreground) can
        // have its single-day fetch resolve AFTER a subsequent load() for a
        // NEWER league has already landed correct data, and this function's
        // unconditional uiState write below would silently stomp it back to
        // the stale league's Loaded state - the real root cause of the
        // Favorites->Schedule flash bug (initially misdiagnosed as a
        // rendering-performance issue across two investigation sessions,
        // before being traced here via direct GamesTab state logging).
        val token = loadToken

        isRefreshing = true
        viewModelScope.launch {
            try {
                val refreshedGames = fetchGamesForLocalDate(targetDate)
                if (token != loadToken) return@launch
                val updatedDays = loadedState.days.map { day ->
                    if (day.date == targetDate) day.copy(games = refreshedGames) else day
                }
                uiState = ScheduleUiState.Loaded(updatedDays)
                // Keep the same-session switch-cache in sync with this
                // day's refreshed data - otherwise a switch-away-and-back
                // within SWITCH_CACHE_TTL_MS would serve the pre-refresh
                // snapshot instead. fetchedAtMs deliberately untouched:
                // only this one day was actually re-fetched, not the whole
                // cached range, so the entry's overall TTL clock shouldn't
                // reset as if everything in it were fresh.
                val cacheKey = cacheKeyFor(currentLeagueGroups)
                scheduleCache[cacheKey]?.let { scheduleCache[cacheKey] = it.copy(days = updatedDays) }
            } catch (e: Exception) {
                // Swallow it: keep showing whatever was already loaded, the
                // spinner stopping is signal enough that it didn't land.
            } finally {
                isRefreshing = false
            }
        }
    }

    // [forceNarrowAround], when set, bypasses [seasonRange] entirely and
    // fetches a narrow +/-[DISPLAY_RANGE_DAYS] window centered on that date
    // instead - used by jumpToDateInternal when the requested date falls
    // outside the loaded seasonRange (see the comment there), since in that
    // case seasonRange's own bounds are exactly what must NOT be used.
    private suspend fun fetchSchedule(forceNarrowAround: LocalDate? = null): List<DayGames> {
        val (start, end) = if (forceNarrowAround != null) {
            forceNarrowAround.minusDays(DISPLAY_RANGE_DAYS) to forceNarrowAround.plusDays(DISPLAY_RANGE_DAYS)
        } else {
            seasonRange ?: (windowCenter.minusDays(DISPLAY_RANGE_DAYS) to windowCenter.plusDays(DISPLAY_RANGE_DAYS))
        }
        val fetched = fetchScheduleChunked(
            start.minusDays(QUERY_BUFFER_DAYS),
            end.plusDays(QUERY_BUFFER_DAYS),
            currentLeagueGroups
        )
        return rebucketByLocalDate(fetched, start, end)
    }

    // Merges every league in [leagueGroups] into one flat DayGames list -
    // rebucketByLocalDate below flattens every league's games together
    // per date anyway, so there's no need to keep each league's chunks
    // separate past this point.
    // Every (league, date-chunk) pair is an independent request - fired all
    // at once via async/awaitAll rather than awaited one at a time in a
    // nested loop (across both chunks AND, in All-Leagues mode, leagues
    // too). A full-season range chunks into ~11-12 pieces
    // (MAX_FETCH_CHUNK_DAYS = 21 against a ~230-250 day season), and each
    // chunk's own real-world latency is ~2-3s (ESPN/backend round-trip) -
    // sequential awaiting was the actual root cause of P1's "40 seconds to
    // open a league" report, confirmed by direct timing against the live
    // backend (3 chunks: 11.2s sequential vs. 3.8s concurrent, the backend
    // itself showing no serialization bottleneck under concurrent load) -
    // not an ESPN fetch problem or a client-side filtering problem, just
    // independent requests that had no reason to wait on each other doing
    // so anyway. Every league currently has a full-season window this long
    // (NBA/MLB/NFL/NHL all span 130-250+ days), so this was never actually
    // specific to "a league with no games today" - that's just when James
    // noticed it most, since that's naturally when he'd wonder why loading
    // was taking so long for an empty result.
    private suspend fun fetchScheduleChunked(start: LocalDate, end: LocalDate, leagueGroups: List<LeagueGroup>): List<DayGames> =
        coroutineScope {
            val deferred = mutableListOf<Deferred<List<DayGames>>>()
            for (leagueGroup in leagueGroups) {
                var chunkStart = start
                while (!chunkStart.isAfter(end)) {
                    val chunkEnd = minOf(chunkStart.plusDays(MAX_FETCH_CHUNK_DAYS - 1), end)
                    val rangeStart = chunkStart
                    val rangeEnd = chunkEnd
                    deferred += async {
                        NetworkGameRepository.schedule(
                            baseUrl = BACKEND_BASE_URL,
                            start = rangeStart,
                            end = rangeEnd,
                            leagueGroup = leagueGroup
                        )
                    }
                    chunkStart = chunkEnd.plusDays(1)
                }
            }
            deferred.awaitAll().flatten()
        }

    private suspend fun fetchGamesForLocalDate(date: LocalDate): List<Game> {
        val fetched = currentLeagueGroups.flatMap { leagueGroup ->
            NetworkGameRepository.schedule(
                baseUrl = BACKEND_BASE_URL,
                start = date.minusDays(QUERY_BUFFER_DAYS),
                end = date.plusDays(QUERY_BUFFER_DAYS),
                leagueGroup = leagueGroup
            )
        }
        return fetched.flatMap { it.games }
            .filter { localDateOf(it) == date }
            .sortedBy { OffsetDateTime.parse(it.tipoffUtc) }
    }

    fun selectDay(index: Int) {
        selectedDayIndex = index
    }
}

private fun localDateOf(game: Game): LocalDate =
    OffsetDateTime.parse(game.tipoffUtc).atZoneSameInstant(ZoneId.systemDefault()).toLocalDate()

// Picks which day-tab to land on within an already-rebucketed [days] list.
// When [preferFirstGameDay] is set (the season hasn't started yet, or has
// already ended with no new one published - see load()'s landsOnSeasonStart),
// the raw [anchor] string is a backend calendar-boundary date that isn't
// necessarily the same LOCAL date the actual season-opener game gets
// rebucketed to (see load()'s comment on this) - so this lands on whichever
// day in the window actually has games instead, only falling back to the
// literal anchor date if the window turns out to have no games at all (e.g.
// a season far enough out that the narrow window doesn't reach it yet).
private fun landingIndex(days: List<DayGames>, anchor: LocalDate, preferFirstGameDay: Boolean): Int {
    if (preferFirstGameDay) {
        val firstGameDayIndex = days.indexOfFirst { it.games.isNotEmpty() }
        if (firstGameDayIndex >= 0) return firstGameDayIndex
    }
    return days.indexOfFirst { it.date == anchor }.coerceAtLeast(0)
}

// CPU-bound (OffsetDateTime.parse per game for grouping + again per game for
// the sort key, times however many games a full season's chunked fetch
// returns - 1000+ for a full NBA season) - off the caller's thread via
// Dispatchers.Default rather than left to run wherever the caller happens to
// be (viewModelScope.launch's default Dispatchers.Main.immediate), which was
// confirmed live to freeze the UI for 1.8-2s (Choreographer "Skipped 110
// frames", two Davey! frames) right as a full-season load lands - visible to
// the user as a stutter/hang exactly when switching to a league whose full
// season just finished loading.
private suspend fun rebucketByLocalDate(fetched: List<DayGames>, start: LocalDate, end: LocalDate): List<DayGames> =
    withContext(Dispatchers.Default) {
        val byLocalDate = fetched.flatMap { it.games }.groupBy(::localDateOf)
        generateSequence(start) { it.plusDays(1) }
            .takeWhile { !it.isAfter(end) }
            .map { date ->
                DayGames(
                    date = date,
                    games = byLocalDate[date].orEmpty().sortedBy { OffsetDateTime.parse(it.tipoffUtc) }
                )
            }
            .toList()
    }
