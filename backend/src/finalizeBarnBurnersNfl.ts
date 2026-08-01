// Takes the 90+ "Barn Burner" NFL games found by investigateNflBarnBurners.ts
// (2021-2023), re-fetches each one's full /summary (a small, known list -
// cheap even though it's a second fetch), and writes a complete
// NflHistoricalGame-shaped record for each to backend/data/nflHistoricalBarnBurners.json -
// the exact interface migrateToGameStore.ts's migrateNflFile() already expects,
// so wiring this in is a one-line addition there, not new migration logic.
//
// The investigation script only kept the aggregate score/tier, not the full
// rubric breakdown (largestDeficitOvercome, leadChanges, etc.) - gameStore
// needs the full breakdown for a real row (History tiles show the full
// breakdown on tap), hence this second, much smaller pass.
//
// Run with: npx tsx src/finalizeBarnBurnersNfl.ts
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { mapGame } from "./backfillRawStatsNfl";
import { computeNflWatchabilityScore, tierForNflScore } from "./nflRubric";

const DATA_DIR = join(__dirname, "..", "data");
const OUTPUT_PATH = join(DATA_DIR, "nflHistoricalBarnBurners.json");
const BASE_PATH = "https://site.api.espn.com/apis/site/v2/sports/football/nfl";
const REQUEST_DELAY_MS = 320;

interface BarnBurner {
  eventId: string;
  date: string;
  away: string;
  home: string;
  awayScore: number;
  homeScore: number;
  finalMargin: number;
  seasonType: number;
  weekNumber?: number;
  score: number;
}


function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function getJson<T>(url: string): Promise<T> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`ESPN request failed: ${res.status} ${res.statusText} (${url})`);
  return (await res.json()) as T;
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

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function fetchSummary(eventId: string): Promise<any> {
  return getJson(`${BASE_PATH}/summary?event=${eventId}`);
}

function loadBarnBurners(): BarnBurner[] {
  const all: BarnBurner[] = [];
  for (const seasonLabel of ["2021", "2022", "2023"]) {
    const path = join(DATA_DIR, `nflBarnBurners_${seasonLabel}.json`);
    if (!existsSync(path)) {
      console.log(`  (skipping ${seasonLabel} - no nflBarnBurners_${seasonLabel}.json yet)`);
      continue;
    }
    const data = JSON.parse(readFileSync(path, "utf8")) as { barnBurners: BarnBurner[] };
    for (const g of data.barnBurners) all.push(g);
  }
  return all;
}

async function main() {
  const candidates = loadBarnBurners();
  console.log(`Finalizing ${candidates.length} candidate NFL Barn Burners (full rubric re-fetch)...`);

  const results = [];
  for (const c of candidates) {
    const summary = await withRetries(() => fetchSummary(c.eventId), `summary ${c.eventId}`);
    await sleep(REQUEST_DELAY_MS);
    if (!summary) {
      console.error(`  COULD NOT FETCH SUMMARY for ${c.eventId} (${c.away} @ ${c.home}) - skipping`);
      continue;
    }

    const mapped = mapGame(c.eventId, String(c.seasonType === 2 ? (c.date.slice(0, 4) as any) : 2023), c.date, summary, c.seasonType, c.weekNumber);
    if (!mapped) {
      console.error(`  ${c.eventId} didn't map to a valid game - skipping`);
      continue;
    }

    const inputs = {
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
    if (breakdown.total < 90) {
      console.error(`  WARNING: ${c.eventId} (${c.away} @ ${c.home}) re-scored at ${breakdown.total.toFixed(0)}, below 90 on re-fetch - excluding`);
      continue;
    }

    results.push({
      eventId: c.eventId,
      date: c.date,
      away: c.away,
      home: c.home,
      awayScore: c.awayScore,
      homeScore: c.homeScore,
      seasonType: c.seasonType,
      weekNumber: c.weekNumber,
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
    });
    console.log(`  OK ${breakdown.total.toFixed(0)}  ${c.away} @ ${c.home}  ${c.date.slice(0, 10)}`);
  }

  writeFileSync(OUTPUT_PATH, JSON.stringify({ games: results }, null, 2), "utf8");
  console.log(`\nWrote ${results.length} games to ${OUTPUT_PATH}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
