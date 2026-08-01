// INVESTIGATION ONLY - not part of the build/server, not wired into
// migrateToGameStore.ts, writes nothing to gameStore/production.
//
// Two-phase, margin-filtered variant of backfillRawStatsNfl.ts, built to
// find only 90+ ("Barn Burner") NFL games across older seasons cheaply -
// same shape as investigateNbaBarnBurners.ts, just applied to football's
// own margin bracket and rubric:
//
// Phase 1 (cheap): loop every day in the season window, fetch just the
// scoreboard (one request/day, no per-game cost), and compute each
// completed game's final margin directly from the scoreboard's own
// competitor scores - no /summary call needed for this.
//
// Phase 2 (expensive, filtered): only for games with margin <= MARGIN_FILTER
// (8 - the NFL rubric's own "one-score game" bracket boundary, see
// nflRubric.ts's marginPoints), fetch the full /summary play-by-play, run it
// through the same mapGame backfillRawStatsNfl.ts uses, and score it with
// computeNflWatchabilityScore. Keep only 90+ results.
//
// Why margin<=8 is safe for 90+ (checked against real data, not just
// reasoned about the point brackets in the abstract - calibrateNflAllTime.ts
// confirmed this directly against the real 572-game 2024+2025 sample: every
// actual 90+ game had margin <= 3, and the single highest score at ANY
// margin above 8 was 63 - not even close to 90). Same empirical-safety-check
// approach investigateNbaBarnBurners.ts's own header describes for NBA's
// margin<=6 filter.
//
// Run with: npx tsx src/investigateNflBarnBurners.ts <season-label>
// e.g.:     npx tsx src/investigateNflBarnBurners.ts 2021
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { dateStringsBetween } from "./dateRange";
import { mapGame, NflRawGame } from "./backfillRawStatsNfl";
import { computeNflWatchabilityScore, NflRubricInputs, tierForNflScore } from "./nflRubric";
import { Tier } from "./rubric";

const DATA_DIR = join(__dirname, "..", "data");
const REQUEST_DELAY_MS = 320; // ~3 requests/sec, same pacing as every other backfill script
const BASE_PATH = "https://site.api.espn.com/apis/site/v2/sports/football/nfl";
const MARGIN_FILTER = 8; // nflRubric.ts's own "one-score game" bracket boundary - see header comment for why this is safe for 90+
const ALL_TIME_MIN_SCORE_NFL = 90;

// Real, tested boundaries (spot-checked directly against ESPN, not assumed):
// season openers land early-to-mid September, Super Bowls land early-to-mid
// February the following calendar year. Generous overshoot on both ends
// (ESPN just returns no events for the empty days) - same convention every
// other backfill script in this codebase uses.
const SEASON_WINDOWS: Record<string, { start: string; end: string }> = {
  "2018": { start: "2018-08-25", end: "2019-02-20" },
  "2019": { start: "2019-08-25", end: "2020-02-20" },
  "2020": { start: "2020-08-25", end: "2021-02-20" },
  "2021": { start: "2021-08-25", end: "2022-02-20" },
  "2022": { start: "2022-08-25", end: "2023-02-20" },
  "2023": { start: "2023-08-25", end: "2024-02-20" },
};

interface EspnScoreboardEvent {
  id: string;
  date: string;
  season?: { type: number; slug: string };
  week?: { number: number };
  competitions: Array<{
    status: { type: { state: string } };
    playByPlayAvailable?: boolean;
    competitors: Array<{ homeAway: "home" | "away"; score: string; team: { displayName: string } }>;
  }>;
}

interface MarginCandidate {
  eventId: string;
  date: string;
  away: string;
  home: string;
  awayScore: number;
  homeScore: number;
  finalMargin: number;
  seasonType: number;
  weekNumber?: number;
}

interface BarnBurner extends MarginCandidate {
  score: number;
  tier: Tier;
}

interface PhaseOneOutput {
  generatedAt: string;
  candidates: MarginCandidate[];
  completedDates: string[];
  totalCompletedGames: number;
}

interface PhaseTwoOutput {
  generatedAt: string;
  barnBurners: BarnBurner[];
  scoredEventIds: string[];
}

async function getJson<T>(url: string): Promise<T> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`ESPN request failed: ${res.status} ${res.statusText} (${url})`);
  return (await res.json()) as T;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function withRetries<T>(fn: () => Promise<T>, label: string, attempts = 3): Promise<T | null> {
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (err) {
      console.error(`  [retry ${i + 1}/${attempts}] ${label} failed: ${(err as Error).message}`);
      if (i < attempts - 1) await sleep(1500 * (i + 1));
    }
  }
  console.error(`  giving up on ${label} after ${attempts} attempts`);
  return null;
}

function loadJson<T>(path: string, fallback: T): T {
  if (!existsSync(path)) return fallback;
  try {
    return JSON.parse(readFileSync(path, "utf8")) as T;
  } catch {
    return fallback;
  }
}

function saveJson(path: string, data: unknown): void {
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  writeFileSync(path, JSON.stringify(data, null, 2), "utf8");
}

async function fetchScoreboard(yyyymmdd: string): Promise<EspnScoreboardEvent[]> {
  const data = await getJson<{ events: EspnScoreboardEvent[] }>(`${BASE_PATH}/scoreboard?dates=${yyyymmdd}`);
  return data.events ?? [];
}

interface NflSummary {
  header: { competitions: Array<{ status: { type: { completed: boolean } } }> };
  scoringPlays?: unknown[];
  boxscore: { teams: unknown[]; players: unknown[] };
}

async function fetchSummary(eventId: string): Promise<NflSummary> {
  return getJson<NflSummary>(`${BASE_PATH}/summary?event=${eventId}`);
}

async function phaseOne(seasonLabel: string, start: string, end: string): Promise<MarginCandidate[]> {
  const outputPath = join(DATA_DIR, `nflBarnBurnerCandidates_${seasonLabel}.json`);
  const output = loadJson<PhaseOneOutput>(outputPath, {
    generatedAt: new Date().toISOString(),
    candidates: [],
    completedDates: [],
    totalCompletedGames: 0,
  });
  const completedDates = new Set(output.completedDates);
  const candidatesById = new Map(output.candidates.map((c) => [c.eventId, c]));
  let totalCompletedGames = output.totalCompletedGames;

  const allDates = dateStringsBetween(start, end);
  const totalDates = allDates.length;
  let processedDates = 0;
  // Logged, not enforced - a sanity check that every candidate game in this
  // season is actually inside the tested-reliable play-by-play window (see
  // this file's header). Any false here for a 2021+ season would mean the
  // real ESPN boundary is patchier than the earlier spot-checks found, worth
  // a second look before trusting phase 2's results.
  let playByPlayUnavailableCount = 0;

  for (const date of allDates) {
    if (completedDates.has(date)) {
      processedDates++;
      continue;
    }

    const yyyymmdd = date.replace(/-/g, "");
    const events = await withRetries(() => fetchScoreboard(yyyymmdd), `scoreboard ${date}`);
    await sleep(REQUEST_DELAY_MS);

    if (events) {
      for (const event of events) {
        if (event.season?.type === 1) continue; // preseason excluded, same rule as backfillRawStatsNfl.ts
        const competition = event.competitions[0];
        if (competition?.status.type.state !== "post") continue;

        const away = competition.competitors.find((c) => c.homeAway === "away");
        const home = competition.competitors.find((c) => c.homeAway === "home");
        if (!away || !home) continue;

        // The Pro Bowl (AFC vs NFC, played the week between Conference
        // Championships and the Super Bowl) is season.type===3 same as real
        // playoff games and slips past every other filter here - confirmed
        // live (2022 and 2023 seasons, event 401492629/401616889): its team
        // names are literally "AFC"/"NFC", not a real franchise. It also
        // happens to carry playByPlayAvailable=false, which kept it out of
        // both of those seasons' actual results by accident (missing data
        // defaulted its lead-changes/comeback dimensions to 0) - not a real
        // guarantee for every future season, so exclude it explicitly here
        // rather than rely on that luck.
        if (away.team.displayName === "AFC" || away.team.displayName === "NFC") continue;
        if (home.team.displayName === "AFC" || home.team.displayName === "NFC") continue;

        totalCompletedGames++;
        if (competition.playByPlayAvailable === false) playByPlayUnavailableCount++;

        const awayScore = parseFloat(away.score) || 0;
        const homeScore = parseFloat(home.score) || 0;
        const finalMargin = Math.abs(homeScore - awayScore);
        if (finalMargin > MARGIN_FILTER) continue;

        candidatesById.set(event.id, {
          eventId: event.id,
          date: event.date,
          away: away.team.displayName,
          home: home.team.displayName,
          awayScore,
          homeScore,
          finalMargin,
          seasonType: event.season?.type ?? 2,
          weekNumber: event.week?.number,
        });
      }
    }

    completedDates.add(date);
    processedDates++;

    output.candidates = Array.from(candidatesById.values());
    output.completedDates = Array.from(completedDates);
    output.totalCompletedGames = totalCompletedGames;
    output.generatedAt = new Date().toISOString();
    saveJson(outputPath, output);

    if (processedDates % 20 === 0 || processedDates === totalDates) {
      console.log(`[Phase 1: ${processedDates}/${totalDates} days] ${date} - ${output.candidates.length} margin<=${MARGIN_FILTER} candidates so far`);
    }
  }

  console.log(`\nPhase 1 done. ${output.candidates.length} candidates out of ${totalCompletedGames} total completed games (margin <= ${MARGIN_FILTER}).`);
  if (playByPlayUnavailableCount > 0) {
    console.log(`  WARNING: ${playByPlayUnavailableCount} completed games had playByPlayAvailable=false - scoringPlays may be missing for those.`);
  }
  return output.candidates;
}

async function phaseTwo(seasonLabel: string, candidates: MarginCandidate[]): Promise<BarnBurner[]> {
  const outputPath = join(DATA_DIR, `nflBarnBurners_${seasonLabel}.json`);
  const output = loadJson<PhaseTwoOutput>(outputPath, { generatedAt: new Date().toISOString(), barnBurners: [], scoredEventIds: [] });
  const scoredIds = new Set(output.scoredEventIds);
  const barnBurnersById = new Map(output.barnBurners.map((g) => [g.eventId, g]));

  let processed = 0;
  for (const candidate of candidates) {
    if (scoredIds.has(candidate.eventId)) {
      processed++;
      continue;
    }

    const summary = await withRetries(() => fetchSummary(candidate.eventId), `summary ${candidate.eventId}`);
    await sleep(REQUEST_DELAY_MS);
    processed++;
    scoredIds.add(candidate.eventId);

    if (summary) {
      const mapped = mapGame(candidate.eventId, seasonLabel, candidate.date, summary as Parameters<typeof mapGame>[3], candidate.seasonType, candidate.weekNumber);
      if (mapped) {
        const inputs: NflRubricInputs = {
          finalMargin: mapped.finalMargin,
          largestDeficitOvercome: mapped.largestDeficitOvercome,
          leadChanges: mapped.leadChanges,
          overtimePeriods: mapped.overtimePeriods,
          decisiveScoreLate: mapped.decisiveScoreLate,
          combinedTurnovers: mapped.combinedTurnovers,
          defensiveOrSpecialTeamsTd: mapped.defensiveOrSpecialTeamsTd,
          maxPassingYards: mapped.maxPassingYards,
          maxRushingYards: mapped.maxRushingYards,
          maxTotalTdsByPlayer: mapped.maxTotalTdsByPlayer,
          totalPoints: mapped.totalPoints,
        };
        const breakdown = computeNflWatchabilityScore(inputs, undefined);
        if (breakdown.total >= ALL_TIME_MIN_SCORE_NFL) {
          barnBurnersById.set(candidate.eventId, { ...candidate, score: breakdown.total, tier: tierForNflScore(breakdown.total) });
        }
      }
    }

    output.barnBurners = Array.from(barnBurnersById.values());
    output.scoredEventIds = Array.from(scoredIds);
    output.generatedAt = new Date().toISOString();
    saveJson(outputPath, output);

    if (processed % 20 === 0 || processed === candidates.length) {
      console.log(`[Phase 2: ${processed}/${candidates.length} candidates scored] ${output.barnBurners.length} Barn Burners (90+) found so far`);
    }
  }

  return Array.from(barnBurnersById.values()).sort((a, b) => b.score - a.score);
}

async function runSeason(seasonLabel: string): Promise<void> {
  const window = SEASON_WINDOWS[seasonLabel];
  if (!window) throw new Error(`No window defined for season ${seasonLabel}`);

  console.log(`\n=== ${seasonLabel} (${window.start} to ${window.end}) ===`);
  const candidates = await phaseOne(seasonLabel, window.start, window.end);
  const barnBurners = await phaseTwo(seasonLabel, candidates);

  console.log(`\n${seasonLabel}: ${barnBurners.length} Barn Burners (90+):`);
  for (const g of barnBurners) {
    console.log(`  ${g.score.toFixed(0)}  ${g.away} @ ${g.home}  (${g.awayScore}-${g.homeScore})  ${g.date.slice(0, 10)}  [${g.tier}]`);
  }
}

async function main() {
  const requestedSeason = process.argv[2];
  const seasons = requestedSeason ? [requestedSeason] : Object.keys(SEASON_WINDOWS);

  for (const seasonLabel of seasons) {
    if (!SEASON_WINDOWS[seasonLabel]) {
      console.error(`Unknown season "${seasonLabel}". Available: ${Object.keys(SEASON_WINDOWS).join(", ")}`);
      process.exit(1);
    }
  }

  for (const seasonLabel of seasons) {
    await runSeason(seasonLabel);
  }

  console.log(`\nAll requested seasons done: ${seasons.join(", ")}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
