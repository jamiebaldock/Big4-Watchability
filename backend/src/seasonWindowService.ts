// Derives the real start/end dates of a league group's current full-season
// browsing range - not a calendar guess, but read directly off ESPN's own
// per-game data. Backs the Games tab's full-season day-tab range/calendar
// picker: the range "start" is the first date with a regular-season-or-later
// game (excluding preseason, per product decision), and "end" is simply the
// latest date ESPN's schedule currently knows about - which is why this
// self-extends once ESPN publishes real playoff/Finals dates, rather than
// needing a guessed Finals-end date hardcoded anywhere.
import { EspnEvent, League, fetchCalendarDates, fetchScoreboard, toEspnDate } from "./espnClient";
import { BasketballLeagueGroup, LEAGUE_GROUPS } from "./gamesService";
import { loadLeagueCache, saveLeagueCache, todayKey } from "./leagueCache";
import { fetchMlbCalendarDates, fetchMlbScoreboard } from "./mlbEspnClient";
import { isRealSeasonEvent } from "./mlbGamesService";
import { fetchNflCalendarGroups } from "./nflEspnClient";
import { fetchNhlCalendarDates, fetchNhlScoreboard } from "./nhlEspnClient";
import { isRealSeasonEvent as isRealNhlSeasonEvent } from "./nhlGamesService";
import { LeagueGroup, SPORT_FOR_LEAGUE_GROUP } from "./types";

export interface SeasonWindow {
  start: string;
  end: string;
}

function isPreseasonEvent(event: EspnEvent): boolean {
  return event.season?.slug === "preseason";
}

/**
 * Scans forward from the earliest known calendar date until it finds one
 * with a real regular-season (or later) game in ANY of the group's member
 * leagues - almost always just a handful of preseason dates to skip past,
 * so this is a small, bounded number of requests, and only ever runs once a
 * day per league group thanks to the cache below. Checking every member
 * league per date (not just one) matters for a multi-league group like
 * NBA's: Summer League dates never show up under the "nba" slug's own
 * scoreboard and vice versa, so a single-league scan would silently miss
 * whichever league isn't currently in its own season.
 */
async function findRegularSeasonStart(leagues: readonly League[], sortedCalendarDates: string[]): Promise<string | undefined> {
  for (const date of sortedCalendarDates) {
    for (const league of leagues) {
      const events = await fetchScoreboard(date.replace(/-/g, ""), league);
      if (events.some((e) => !isPreseasonEvent(e))) return date;
    }
  }
  return undefined;
}

// Confirmed live 2026-07-29: fetchCalendarDates(today, league) during the
// real gap between one season's Finals and the next one's preseason
// returns the *previous* season's calendar - ESPN's own season pointer for
// a query date doesn't roll over to the new season until queried near/
// within it (confirmed: querying "today" still returned the 2025-26
// calendar ending 2026-06-13, while querying October 6 2026 directly
// already returns the real, live 2026-27 calendar). Left unhandled, this
// stale window becomes the app's whole notion of "the season" until ESPN's
// own pointer rolls over on its own - "Go to Today" then can't find today
// in the loaded (stale, months-old) day range and falls back to the first
// loaded day, landing on last season's opening night instead of anything
// resembling "today". Probes forward at increasing offsets (not a single
// fixed guess, since the real gap's length varies by league/year) until a
// calendar whose own end date is at or after the probe point is found,
// which in practice picks up the new season the moment ESPN's pointer for
// that later date has already flipped - same "don't trust a stale array,
// go find the real one" fix as getNextScheduledDate's own fallback in
// gamesService.ts, which hit the identical root cause.
const GAP_PROBE_OFFSETS_DAYS = [30, 60, 90, 120, 150];
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

/** Union of every member league's own calendar at [anchorDate] - see findRegularSeasonStart's comment for why a single-league fetch isn't enough for a group like NBA's that spans several separate ESPN "leagues". */
async function unionCalendarAt(leagues: readonly League[], anchorDate: Date): Promise<string[]> {
  const perLeague = await Promise.all(leagues.map((league) => fetchCalendarDates(toEspnDate(anchorDate), league)));
  return [...new Set(perLeague.flat())].sort();
}

async function getBasketballSeasonWindow(leagueGroup: BasketballLeagueGroup): Promise<SeasonWindow | null> {
  const now = new Date();
  const leagues = LEAGUE_GROUPS[leagueGroup];
  const nowIso = isoDate(now);

  let allDates = await unionCalendarAt(leagues, now);
  const isStale = allDates.length > 0 && allDates[allDates.length - 1] < nowIso;

  if (allDates.length === 0 || isStale) {
    // Probe forward at increasing offsets (not a single fixed guess, since
    // the real gap's length varies by league/year) for a genuinely
    // different (newer) calendar - see the header comment above
    // GAP_PROBE_OFFSETS_DAYS for the full reasoning.
    const staleEnd = allDates[allDates.length - 1] ?? "";
    for (const offsetDays of GAP_PROBE_OFFSETS_DAYS) {
      const probeDate = new Date(now.getTime() + offsetDays * ONE_DAY_MS);
      const probed = await unionCalendarAt(leagues, probeDate);
      if (probed.length > 0 && probed[probed.length - 1] > staleEnd) {
        allDates = probed;
        break;
      }
    }
  }
  if (allDates.length === 0) return null;

  const end = allDates[allDates.length - 1];
  // findRegularSeasonStart deliberately excludes preseason - correct once
  // the real regular season is actually in ESPN's system, but confirmed
  // live 2026-07-29 that it isn't always there yet even once the *new*
  // season's calendar starts appearing: NBA's 2026-27 schedule was only
  // published as far as its preseason window (Oct 5-16) as of this probe,
  // full regular-season dates weren't loaded into ESPN's system yet
  // (their own full-schedule release timeline runs behind the preseason
  // one). Falling back to the earliest known date in that case still gives
  // a real, current window (this season's actual preseason opener) instead
  // of either staying on last season's stale dates or returning null - and
  // self-corrects the moment ESPN adds real regular-season dates, since
  // this whole function re-runs fresh once daily.
  const start = (await findRegularSeasonStart(leagues, allDates)) ?? allDates[0];

  return { start, end };
}

function isoDate(d: Date): string {
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

// MLB's own scoreboard calendar (fetchMlbCalendarDates) does NOT densely
// enumerate every regular-season date the way basketball's does - confirmed
// directly against a real response: querying it mid-season returned only 48
// entries total for the whole year (spring training's first day, two
// All-Star-break dates, then every postseason date from late September
// onward), with the entire ~6-month regular season in between completely
// absent. findRegularSeasonStart's "scan the calendar day by day" approach
// above would silently skip straight from spring training to the All-Star
// break and misreport the season as starting in mid-July, so MLB instead
// scans real calendar days directly via fetchMlbScoreboard (confirmed to
// return real per-day results, e.g. 8 games on the real 2026 Opening Day of
// March 27) starting from March 1 - regular season always begins in the back
// half of March, so 60 days is a generous bound that exits early (in
// practice within ~4 weeks) once the first non-spring-training date is
// found.
async function findMlbRegularSeasonStart(seasonYear: number): Promise<string | undefined> {
  const marchFirst = Date.UTC(seasonYear, 2, 1);
  const oneDayMs = 24 * 60 * 60 * 1000;
  for (let i = 0; i < 60; i++) {
    const date = new Date(marchFirst + i * oneDayMs);
    const events = await fetchMlbScoreboard(toEspnDate(date));
    if (events.some(isRealSeasonEvent)) return isoDate(date);
  }
  return undefined;
}

/**
 * MLB analogue of getBasketballSeasonWindow - "end" is still the calendar's
 * own latest known date (same self-extending reasoning as basketball's: the
 * calendar's sparse regular-season dates don't matter for this half, since
 * its postseason tail is densely enumerated well before postseason actually
 * starts). "start" comes from findMlbRegularSeasonStart's direct scoreboard
 * scan instead, since the calendar can't be used for that half (see its
 * comment).
 */
async function getMlbSeasonWindow(): Promise<SeasonWindow | null> {
  const now = new Date();
  const allDates = (await fetchMlbCalendarDates(toEspnDate(now))).sort();
  if (allDates.length === 0) return null;

  const end = allDates[allDates.length - 1];
  const start = await findMlbRegularSeasonStart(now.getUTCFullYear());
  if (!start) return null;

  return { start, end };
}

// NFL's calendar directly labels its Regular Season/Postseason groups with
// real startDate/endDate (see nflEspnClient.ts's own comment on this shape)
// - no day-by-day scan needed the way MLB's sparse calendar requires.
// "start" is the Regular Season group's own startDate (preseason, value
// "1", deliberately excluded - same "skip preseason" rule as everywhere
// else in this build); "end" is the Postseason group's endDate if it
// exists yet, falling back to the Regular Season's own endDate otherwise
// (e.g. mid-season, before the postseason group's real dates are known).
async function getNflSeasonWindow(): Promise<SeasonWindow | null> {
  const groups = await fetchNflCalendarGroups(toEspnDate(new Date()));
  const regularSeason = groups.find((g) => g.value === "2");
  if (!regularSeason) return null;
  const postseason = groups.find((g) => g.value === "3");

  return {
    start: regularSeason.startDate.slice(0, 10),
    end: (postseason ?? regularSeason).endDate.slice(0, 10)
  };
}

// NHL's calendar is dense/flat like basketball's (confirmed directly, ~226
// real dates spanning the full season) - same findRegularSeasonStart-style
// scan works, just against NHL's own single-league scoreboard/calendar
// rather than unioning multiple basketball "leagues".
async function findNhlRegularSeasonStart(sortedCalendarDates: string[]): Promise<string | undefined> {
  for (const date of sortedCalendarDates) {
    const events = await fetchNhlScoreboard(date.replace(/-/g, ""));
    if (events.some(isRealNhlSeasonEvent)) return date;
  }
  return undefined;
}

/** NHL analogue of freshestCalendar above - same stale-during-the-gap fix, confirmed live 2026-07-29 (NHL's own season-window was returning 2025-26's calendar, not 2026-27's), just against fetchNhlCalendarDates's single-league shape instead of basketball's per-league one. */
async function freshestNhlCalendar(now: Date, staleCalendar: string[]): Promise<string[]> {
  if (staleCalendar.length === 0) return staleCalendar;
  const nowIso = isoDate(now);
  const staleEnd = staleCalendar[staleCalendar.length - 1];
  if (staleEnd >= nowIso) return staleCalendar;

  for (const offsetDays of GAP_PROBE_OFFSETS_DAYS) {
    const probeDate = new Date(now.getTime() + offsetDays * ONE_DAY_MS);
    const probeCalendar = await fetchNhlCalendarDates(toEspnDate(probeDate));
    if (probeCalendar.length > 0 && probeCalendar[probeCalendar.length - 1] > staleEnd) {
      return probeCalendar;
    }
  }
  return staleCalendar;
}

/** NHL analogue of getBasketballSeasonWindow - same "end = calendar's own latest date, start = scan forward for first real regular-season game" shape, just against NHL's single flat calendar instead of unioning several basketball "leagues". */
async function getNhlSeasonWindow(): Promise<SeasonWindow | null> {
  const now = new Date();
  const rawCalendar = await fetchNhlCalendarDates(toEspnDate(now));
  const allDates = (await freshestNhlCalendar(now, rawCalendar)).sort();
  if (allDates.length === 0) return null;

  const end = allDates[allDates.length - 1];
  const start = await findNhlRegularSeasonStart(allDates);
  if (!start) return null;

  return { start, end };
}

/** Cached once per calendar day per league group - same reasoning as standings/stats (ESPN's schedule doesn't change meaningfully more often than that). */
export async function getSeasonWindow(leagueGroup: LeagueGroup): Promise<SeasonWindow | null> {
  // Basketball, MLB, NFL, and now NHL all have a full-season browse/
  // calendar-picker route built - every other LeagueGroup still falls
  // through to null, the same "nothing to show yet" signal
  // GameListViewModel.kt's own comment says this endpoint is already
  // expected to return gracefully, not an error state. Checked before the
  // cache/basketball fallback below, which would otherwise crash indexing
  // LEAGUE_GROUPS with a leagueGroup it doesn't recognize.
  const sport = SPORT_FOR_LEAGUE_GROUP[leagueGroup];
  if (sport !== "basketball" && sport !== "baseball" && sport !== "football" && sport !== "hockey") return null;

  const dateKey = todayKey(new Date());
  const cached = loadLeagueCache<SeasonWindow>("seasonWindow", leagueGroup, dateKey);
  if (cached) return cached;

  // Safe cast: the SPORT_FOR_LEAGUE_GROUP guard above already ruled out
  // every basketball-sport LeagueGroup value other than "nba" | "wnba".
  const window =
    sport === "baseball"
      ? await getMlbSeasonWindow()
      : sport === "football"
        ? await getNflSeasonWindow()
        : sport === "hockey"
          ? await getNhlSeasonWindow()
          : await getBasketballSeasonWindow(leagueGroup as BasketballLeagueGroup);
  if (!window) return null;

  saveLeagueCache("seasonWindow", leagueGroup, dateKey, window);
  return window;
}
