// Takes every 90+ "Barn Burner" found by investigateNba2023.ts (2023-24)
// and investigateNbaBarnBurners.ts (2022-23 through 2017-18), re-fetches
// each one's full /summary (a small, known list - cheap even though it's a
// second fetch), and writes a complete HistoricalGame-shaped record for
// each to backend/data/historicalWatchabilityBarnBurners.json - the exact
// interface migrateToGameStore.ts's migrateFile() already expects (same
// shape as historicalWatchability.json), so wiring this in is a one-line
// addition there, not new migration logic.
//
// The investigation scripts only kept the aggregate score/tier, not the
// full rubric breakdown (largestDeficitOvercome, leadChanges, clutch flags,
// etc.) - gameStore needs the full breakdown for a real row (History tiles
// show the full breakdown on tap), hence this second, much smaller pass.
//
// Run with: npx tsx src/finalizeBarnBurners.ts
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fetchSummary } from "./espnClient";
import { mapEventToGame } from "./gameMapper";
import { computeWatchabilityScore, tierForScore } from "./rubric";

const DATA_DIR = join(__dirname, "..", "data");
const OUTPUT_PATH = join(DATA_DIR, "historicalWatchabilityBarnBurners.json");
const REQUEST_DELAY_MS = 320;

interface RawCandidate {
  eventId: string;
  date: string;
  away: string;
  home: string;
  awayScore: number;
  homeScore: number;
  season: string;
}

// 2023-24's single 90+ game came from investigateNba2023.ts, a differently-
// named/shaped output file than the later seasons - included explicitly
// here rather than special-cased file-reading logic for one entry.
const MANUAL_ENTRIES: RawCandidate[] = [
  {
    eventId: "401585278",
    date: "2024-01-28T01:30Z",
    away: "Los Angeles Lakers",
    home: "Golden State Warriors",
    awayScore: 145,
    homeScore: 144,
    season: "2023-24",
  },
];

const SEASON_LABELS = ["2022-23", "2021-22", "2020-21", "2019-20", "2018-19", "2017-18"];

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

function loadCandidates(): RawCandidate[] {
  const all: RawCandidate[] = [...MANUAL_ENTRIES];
  for (const season of SEASON_LABELS) {
    const path = join(DATA_DIR, `barnBurners_${season}.json`);
    if (!existsSync(path)) {
      console.log(`  (skipping ${season} - no barnBurners_${season}.json yet)`);
      continue;
    }
    const data = JSON.parse(readFileSync(path, "utf8")) as { barnBurners: Array<Omit<RawCandidate, "season">> };
    for (const g of data.barnBurners) all.push({ ...g, season });
  }
  return all;
}

async function main() {
  const candidates = loadCandidates();
  console.log(`Finalizing ${candidates.length} candidate Barn Burners (full rubric re-fetch)...`);

  const results = [];
  for (const c of candidates) {
    const summary = await withRetries(() => fetchSummary(c.eventId, "nba"), `summary ${c.eventId}`);
    await sleep(REQUEST_DELAY_MS);
    if (!summary) {
      console.error(`  COULD NOT FETCH SUMMARY for ${c.eventId} (${c.away} @ ${c.home}, ${c.season}) - skipping`);
      continue;
    }

    const fakeEvent = {
      id: c.eventId,
      date: c.date,
      competitions: [
        {
          status: { period: 0, displayClock: "", type: { state: "post" as const, completed: true } },
          competitors: [
            { id: "away", homeAway: "away" as const, team: { displayName: c.away } as any, score: String(c.awayScore) },
            { id: "home", homeAway: "home" as const, team: { displayName: c.home } as any, score: String(c.homeScore) },
          ],
        },
      ],
    };

    const mapped = mapEventToGame(fakeEvent as any, "nba", summary);
    if (mapped.status !== "final" || mapped.rubric.finalMargin == null) {
      console.error(`  ${c.eventId} didn't map to a final game with a margin - skipping`);
      continue;
    }
    const breakdown = computeWatchabilityScore(mapped.rubric, undefined, "nba");
    if (breakdown.total < 90) {
      console.error(`  WARNING: ${c.eventId} (${c.away} @ ${c.home}) re-scored at ${breakdown.total.toFixed(0)}, below 90 on re-fetch - excluding`);
      continue;
    }

    results.push({
      eventId: c.eventId,
      season: c.season,
      date: c.date,
      away: c.away,
      home: c.home,
      awayScore: c.awayScore,
      homeScore: c.homeScore,
      finalMargin: mapped.rubric.finalMargin,
      largestDeficitOvercome: mapped.rubric.largestDeficitOvercome ?? 0,
      leadChanges: mapped.rubric.leadChanges ?? 0,
      overtimePeriods: mapped.rubric.overtimePeriods,
      closeInFinalTwoMin: mapped.rubric.closeInFinalTwoMin,
      leadChangeInFinalMin: mapped.rubric.leadChangeInFinalMin,
      decidedOnFinalPossession: mapped.rubric.decidedOnFinalPossession,
      starPerformance: mapped.rubric.starPerformance,
      buzzerBeater: mapped.rubric.buzzerBeater,
      score: breakdown.total,
      tier: tierForScore(breakdown.total),
    });
    console.log(`  OK ${breakdown.total.toFixed(0)}  ${c.away} @ ${c.home}  ${c.season}  ${c.date.slice(0, 10)}`);
  }

  writeFileSync(OUTPUT_PATH, JSON.stringify({ games: results }, null, 2), "utf8");
  console.log(`\nWrote ${results.length} games to ${OUTPUT_PATH}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
