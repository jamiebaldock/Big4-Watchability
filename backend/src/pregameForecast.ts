// Pre-game forecast instrumentation (added 2026-10-28).
//
// WHY THIS EXISTS, and what it deliberately does NOT do.
//
// The original idea was a matchup rubric: "based on past games, how likely is
// it that these two teams produce a high-watchability game?" That was tested
// against the real 2024+ data before any of it was built, and it does not
// work. Splitting each league chronologically and asking whether a pairing's
// average score in the first half predicts its average in the second half
// gives r = 0.014 (MLB), 0.044 (NBA), -0.023 (NHL), 0.044 (WNBA) across ~1360
// pairings. That is noise.
//
// It cannot work on this data either, for a structural reason extra seasons
// won't fix soon: game-level score has a standard deviation of ~19 points and
// the median pairing has only 4-9 meetings (NFL: 1). A pairing average over 5
// games carries a standard error of +/-8.5 points - the real spread between
// pairings is smaller than the error bar on measuring it. Team-level tendency
// fails the same way: it looks real within a window (NBA r=0.41) but that is
// current form leaking across the split, and season-over-season it decays to
// 0.12-0.27 on n~30 and goes NEGATIVE for NHL. Rivalry games (proxied by
// meeting frequency) came out +0.6 to +2.5 points with every confidence
// interval crossing zero.
//
// So instead of shipping a confident-looking random number, this module
// captures the one thing that is irrecoverable if we don't capture it now:
// each team's record AS OF TIPOFF. Standings are a moving target - once a
// game is played, the record the teams carried into it is gone from every
// live API we have. Two good teams close together in the table is the one
// pre-game signal with a plausible mechanism behind it, and it is precisely
// the signal that could not be tested, because it was never stored.
//
// The forecast number itself is secondary and openly uncalibrated: the stored
// inputs mean any formula can be recomputed retroactively, so v1 exists only
// to have something to grade. See gradePregameForecast.ts.
//
// IMPORTANT: this is instrumentation, not a feature. Nothing here is exposed
// to the apps, and nothing here touches `stakes` - see the warning on
// forecastVersion below.

import { setPregameSnapshot } from "./gameStore";

/** Bumped whenever the v1 formula below changes, so a later tweak can't silently contaminate an already-collected dataset. Grade one version at a time. */
export const FORECAST_VERSION = "v1";

export interface ParsedRecord {
  wins: number;
  losses: number;
  /** The third number, where a league has one: NHL OT/shootout losses ("7-3-1"), NFL ties ("1-4-1"). Zero for the two-part leagues. */
  otLosses: number;
  /**
   * 0..1. For two-part records this is plain W/(W+L). For three-part records
   * the third number counts as half a win:
   *
   *   NHL "7-3-1" - an OT/shootout loss. Half a win is arithmetically
   *     identical to the standings points percentage the league itself ranks
   *     by, so this reads 0.682, not the 0.700 a naive two-part parse that
   *     silently dropped the third number would give.
   *   NFL "1-4-1" - a tie, which genuinely IS worth half a win in the NFL
   *     standings. Same arithmetic, same correct answer, by luck rather than
   *     design - but verified against a real row (Commanders, 2026-10-28)
   *     rather than assumed, so it is design now.
   */
  winPct: number;
}

/**
 * Parses ESPN's `records[type=total].summary`. Verified against live ESPN on
 * 2026-10-28 for all four sports: NBA "2-2", NFL "5-1", MLB "98-64",
 * NHL "7-3-1". Returns null for anything unparseable or a 0-game record
 * (preseason openers, where a 0-0 win pct would be a meaningless 0 rather
 * than genuinely "bad"), so callers can skip rather than store a fake.
 */
export function parseRecord(summary: string | undefined | null): ParsedRecord | null {
  if (!summary) return null;
  const parts = summary.trim().split("-");
  if (parts.length < 2 || parts.length > 3) return null;

  const nums = parts.map((p) => Number(p));
  if (nums.some((n) => !Number.isFinite(n) || n < 0)) return null;

  const [wins, losses, otLosses = 0] = nums;
  const games = wins + losses + otLosses;
  if (games === 0) return null;

  return { wins, losses, otLosses, winPct: (wins + 0.5 * otLosses) / games };
}

export interface ForecastInputs {
  awayWinPct: number;
  homeWinPct: number;
  /** Derived from the already-persisted season_stage_label, not re-sniffed from ESPN. */
  isPostseason: boolean;
}

/**
 * A 0-100 "outlook" index. Higher means a better game is expected.
 *
 * READ THIS BEFORE USING THE NUMBER FOR ANYTHING. The scale is NOT the
 * watchability score's scale and is not comparable to it - league score
 * averages run 22-39, so an outlook of 60 does not predict a score of 60. The
 * absolute values are arbitrary until there is enough outcome data to
 * calibrate against, which is the entire point of collecting this. Only the
 * ORDERING is meaningful, and even that is an untested hypothesis right now,
 * which is why gradePregameForecast.ts reports rank correlation.
 *
 * Two ingredients, both chosen because they have a mechanism rather than
 * because they tested well (nothing tested well):
 *   quality  - two good teams should beat two bad ones
 *   evenness - a mismatch invites a blowout, and margin is the single
 *              heaviest term in every league's rubric
 * Evenness is weighted higher of the two for that reason.
 *
 * KNOWN LIMITATION, not worth fixing yet: it is at its worst in the first
 * weeks of a season, when a 4-0 record is three games of evidence and reads
 * as a perfect 1.000. The live run on 2026-10-28 duly rated Grizzlies (4-0)
 * at Blazers (3-0) a flat 100. The fix is to shrink win pct toward .500 by
 * games played - but picking the shrinkage constant out of the air is the
 * same mistake as inventing the matchup rubric was, so it waits for outcome
 * data. pre_away_win_pct/pre_home_win_pct are stored precisely so a v2 can
 * do it properly later, and the raw records are there to recover games
 * played from.
 */
export function pregameForecastV1({ awayWinPct, homeWinPct, isPostseason }: ForecastInputs): number {
  const quality = (awayWinPct + homeWinPct) / 2;
  const evenness = 1 - Math.abs(awayWinPct - homeWinPct);

  // Evenness pays off in PROPORTION to quality rather than on top of it.
  // Adding the two independently was the first cut, and the first live run
  // showed why it was wrong: Kings (0-4) at Pelicans (0-3) scored 60 out of
  // 100, because two winless teams are perfectly evenly matched and so
  // collected the entire evenness term. "Equally bad" is not "equally good",
  // and no amount of closeness makes two winless teams a must-watch.
  // Multiplying keeps the mechanism (a mismatch invites a blowout, and margin
  // is the heaviest term in every league's rubric) while making it conditional
  // on there being some quality to be even about. The 0.4 floor stops it
  // collapsing to zero, since a tight game between two bad teams is still
  // more watchable than a 40-point blowout between them.
  const raw = 40 * quality + 60 * evenness * (0.4 + 0.6 * quality);
  // Flat postseason bump: elimination stakes are real and apply to every
  // playoff game equally. Deliberately crude - if the data later says the
  // effect differs by round, that is a v2 with its own version stamp.
  const withStage = raw + (isPostseason ? 10 : 0);

  return Math.round(Math.max(0, Math.min(100, withStage)));
}

/** True for the postseason labels deriveCompetitionLabel/deriveNhlCompetitionLabel already produce ("NBA - Playoffs: ...", "MLB - Playoffs: World Series"). */
export function isPostseasonLabel(label: string | null | undefined): boolean {
  return (label ?? "").toLowerCase().includes("playoff");
}

/** The shape every sport's ESPN competitor shares, as far as this module cares. */
interface CompetitorWithRecords {
  records?: Array<{ name: string; type: string; summary: string }>;
}

function totalRecordSummary(competitor: CompetitorWithRecords): string | undefined {
  return competitor.records?.find((r) => r.type === "total")?.summary;
}

/**
 * Captures one game's pre-game snapshot. Safe and cheap to call on every
 * sighting of a game in any status - gameStore.setPregameSnapshot's
 * status='upcoming' guard handles both the refresh-while-upcoming behaviour
 * and the automatic freeze at tipoff, so callers don't branch on status.
 *
 * Silently does nothing when either record is missing or unparseable, which
 * is the right outcome for a season opener (0-0, no information) or a
 * preseason game ESPN gives no record for: a NULL snapshot honestly means
 * "not known", whereas a stored 0.000 win pct would read as two terrible
 * teams and quietly poison the dataset this exists to build.
 */
export function capturePregameSnapshot(
  eventId: string,
  awayCompetitor: CompetitorWithRecords,
  homeCompetitor: CompetitorWithRecords,
  seasonStageLabel: string | null | undefined
): void {
  const awayRaw = totalRecordSummary(awayCompetitor);
  const homeRaw = totalRecordSummary(homeCompetitor);
  const away = parseRecord(awayRaw);
  const home = parseRecord(homeRaw);
  if (!away || !home) return;

  setPregameSnapshot(eventId, {
    awayRecord: awayRaw!,
    homeRecord: homeRaw!,
    awayWinPct: away.winPct,
    homeWinPct: home.winPct,
    forecast: pregameForecastV1({
      awayWinPct: away.winPct,
      homeWinPct: home.winPct,
      isPostseason: isPostseasonLabel(seasonStageLabel),
    }),
    forecastVersion: FORECAST_VERSION,
  });
}
