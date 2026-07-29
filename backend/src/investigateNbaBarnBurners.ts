// INVESTIGATION ONLY - not part of the build/server, not wired into
// migrateToGameStore.ts, writes nothing to gameStore/production.
//
// Two-phase, margin-filtered variant of investigateNba2023.ts, built to
// find only 90+ ("Barn Burner") games across older NBA seasons cheaply:
//
// Phase 1 (cheap): loop every day in the season window, fetch just the
// scoreboard (one request/day, no per-game cost), and compute each
// completed game's final margin directly from the scoreboard's own
// competitor scores - no /summary call needed for this.
//
// Phase 2 (expensive, filtered): only for games with margin <= MARGIN_FILTER
// (6 - the rubric's own m<=6 bracket boundary), fetch the full /summary
// play-by-play and run it through the exact same mapEventToGame/
// computeWatchabilityScore the live app uses, then keep only 90+ results.
//
// Why margin<=6 is safe for 90+ specifically (not just a guess): every
// non-margin rubric dimension maxes out at 85 points combined, and the two
// biggest individual pieces of that 85 (buzzer-beater's 10, decided-on-
// final-possession's 6) can only be true when the margin is already tiny
// (both are defined as the deciding shot landing in the final 3-24 seconds
// AND flipping the leader - mathematically incompatible with anything but
// a ~1-3 point final margin). Confirmed against the real, fully-scored
// 2023-24 season (investigateNba2023.ts): every one of that season's 22
// 70+ games had margin <= 3, and the single highest score at any margin
// above 3 was 69 (not even Worth-Your-Time tier).
//
// Run with: npx tsx src/investigateNbaBarnBurners.ts <season-label>
// e.g.:     npx tsx src/investigateNbaBarnBurners.ts 2022-23
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { dateStringsBetween } from "./dateRange";
import { fetchScoreboard, fetchSummary } from "./espnClient";
import { mapEventToGame } from "./gameMapper";
import { computeWatchabilityScore, Tier, tierForScore } from "./rubric";

const DATA_DIR = join(__dirname, "..", "data");
const REQUEST_DELAY_MS = 320; // ~3 requests/sec
const MARGIN_FILTER = 6; // rubric.ts's own m<=6 bracket boundary - see header comment for why this is safe for 90+

// Real season boundaries, each overshooting slightly on both ends (ESPN
// just returns no events for the empty days) - same convention every other
// backfill script in this codebase uses. 2019-20 and 2020-21 are genuinely
// unusual (COVID suspension/bubble restart, and the delayed 72-game season
// respectively) - windows widened accordingly rather than assuming a normal
// Oct-June shape.
const SEASON_WINDOWS: Record<string, { start: string; end: string }> = {
  "2022-23": { start: "2022-10-01", end: "2023-06-20" },
  "2021-22": { start: "2021-10-01", end: "2022-06-25" },
  "2020-21": { start: "2020-12-10", end: "2021-07-25" },
  "2019-20": { start: "2019-10-15", end: "2020-10-20" },
  "2018-19": { start: "2018-10-01", end: "2019-06-20" },
  "2017-18": { start: "2017-10-01", end: "2018-06-15" },
};

interface MarginCandidate {
  eventId: string;
  date: string;
  away: string;
  home: string;
  awayScore: number;
  homeScore: number;
  finalMargin: number;
}

interface BarnBurner extends MarginCandidate {
  score: number;
  tier: Tier;
}

interface PhaseOneOutput {
  generatedAt: string;
  candidates: MarginCandidate[];
  completedDates: string[];
}

interface PhaseTwoOutput {
  generatedAt: string;
  barnBurners: BarnBurner[];
  scoredEventIds: string[];
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

async function phaseOne(seasonLabel: string, start: string, end: string): Promise<MarginCandidate[]> {
  const outputPath = join(DATA_DIR, `barnBurnerCandidates_${seasonLabel}.json`);
  const output = loadJson<PhaseOneOutput>(outputPath, { generatedAt: new Date().toISOString(), candidates: [], completedDates: [] });
  const completedDates = new Set(output.completedDates);
  const candidatesById = new Map(output.candidates.map((c) => [c.eventId, c]));

  const allDates = dateStringsBetween(start, end);
  const totalDates = allDates.length;
  let processedDates = 0;
  let totalCompletedGames = 0;

  for (const date of allDates) {
    if (completedDates.has(date)) {
      processedDates++;
      continue;
    }

    const yyyymmdd = date.replace(/-/g, "");
    const events = await withRetries(() => fetchScoreboard(yyyymmdd, "nba"), `scoreboard ${date}`);
    await sleep(REQUEST_DELAY_MS);

    if (events) {
      for (const event of events) {
        if (event.season?.slug === "preseason") continue;
        const competition = event.competitions[0];
        if (competition?.status.type.state !== "post") continue;

        const away = competition.competitors.find((c) => c.homeAway === "away");
        const home = competition.competitors.find((c) => c.homeAway === "home");
        if (!away || !home) continue;

        totalCompletedGames++;
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
        });
      }
    }

    completedDates.add(date);
    processedDates++;

    output.candidates = Array.from(candidatesById.values());
    output.completedDates = Array.from(completedDates);
    output.generatedAt = new Date().toISOString();
    saveJson(outputPath, output);

    if (processedDates % 20 === 0 || processedDates === totalDates) {
      console.log(`[Phase 1: ${processedDates}/${totalDates} days] ${date} - ${output.candidates.length} margin<=${MARGIN_FILTER} candidates so far`);
    }
  }

  console.log(`\nPhase 1 done. ${output.candidates.length} candidates out of ${totalCompletedGames} total completed games (margin <= ${MARGIN_FILTER}).`);
  return output.candidates;
}

async function phaseTwo(seasonLabel: string, candidates: MarginCandidate[]): Promise<BarnBurner[]> {
  const outputPath = join(DATA_DIR, `barnBurners_${seasonLabel}.json`);
  const output = loadJson<PhaseTwoOutput>(outputPath, { generatedAt: new Date().toISOString(), barnBurners: [], scoredEventIds: [] });
  const scoredIds = new Set(output.scoredEventIds);
  const barnBurnersById = new Map(output.barnBurners.map((g) => [g.eventId, g]));

  let processed = 0;
  for (const candidate of candidates) {
    if (scoredIds.has(candidate.eventId)) {
      processed++;
      continue;
    }

    const summary = await withRetries(() => fetchSummary(candidate.eventId, "nba"), `summary ${candidate.eventId}`);
    await sleep(REQUEST_DELAY_MS);
    processed++;
    scoredIds.add(candidate.eventId);

    if (summary) {
      // Reconstruct a minimal EspnEvent shape mapEventToGame expects, reusing
      // the candidate's already-known fields rather than re-deriving them.
      const fakeEvent = {
        id: candidate.eventId,
        date: candidate.date,
        competitions: [
          {
            status: { period: 0, displayClock: "", type: { state: "post" as const, completed: true } },
            competitors: [
              { id: "away", homeAway: "away" as const, team: { displayName: candidate.away } as any, score: String(candidate.awayScore) },
              { id: "home", homeAway: "home" as const, team: { displayName: candidate.home } as any, score: String(candidate.homeScore) },
            ],
          },
        ],
      };
      const mapped = mapEventToGame(fakeEvent as any, "nba", summary);
      if (mapped.status === "final" && mapped.rubric.finalMargin != null) {
        const breakdown = computeWatchabilityScore(mapped.rubric, undefined, "nba");
        if (breakdown.total >= 90) {
          barnBurnersById.set(candidate.eventId, { ...candidate, score: breakdown.total, tier: tierForScore(breakdown.total) });
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

async function main() {
  const seasonLabel = process.argv[2];
  const window = seasonLabel ? SEASON_WINDOWS[seasonLabel] : undefined;
  if (!window) {
    console.error(`Usage: npx tsx src/investigateNbaBarnBurners.ts <season-label>`);
    console.error(`Available: ${Object.keys(SEASON_WINDOWS).join(", ")}`);
    process.exit(1);
  }

  console.log(`=== ${seasonLabel} (${window.start} to ${window.end}) ===`);
  const candidates = await phaseOne(seasonLabel, window.start, window.end);
  const barnBurners = await phaseTwo(seasonLabel, candidates);

  console.log(`\n${seasonLabel}: ${barnBurners.length} Barn Burners (90+):`);
  for (const g of barnBurners) {
    console.log(`  ${g.score.toFixed(0)}  ${g.away} @ ${g.home}  (${g.awayScore}-${g.homeScore})  ${g.date.slice(0, 10)}  [${g.tier}]`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
