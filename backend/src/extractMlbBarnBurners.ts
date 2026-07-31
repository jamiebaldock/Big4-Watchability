// Reads the 21 raw per-season MLB backfill files (mlbRawStats_2003.json
// through mlbRawStats_2023.json - backfillRawStatsMlbHistorical.ts, ~50k
// games, gitignored/local-only, regenerable by rerunning that script) and
// writes the small curated result (mlbHistoricalBarnBurners.json) that
// actually gets committed and migrated into gameStore: only the games that
// clear MLB's own All-time bar (ALL_TIME_MIN_SCORE_MLB in the mobile app's
// HistoryScreen.kt - keep the two in sync if that threshold ever changes).
//
// This is the standard shape for every league's older-seasons backfill
// going forward (James's explicit call, 2026-07-31, after MLB's own full
// 21-season migration turned out to keep ~50k rows live in gameStore for a
// benefit that came down to 8 games - see migrateToGameStore.ts's own
// comment on pruneOlderSeasonsExcept for the full story): collect and
// score full seasons locally to find what clears the bar, but only ever
// migrate/commit the handful of games that actually do. Mirrors NBA's
// original investigateNbaBarnBurners.ts/finalizeBarnBurners.ts approach,
// just run as a second extraction pass over already-collected data here
// instead of a margin-filtered live search.
//
// Run with: npx tsx src/extractMlbBarnBurners.ts
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { computeMlbWatchabilityScore, MlbRubricInputs } from "./mlbRubric";
import { MlbRawGame } from "./backfillRawStatsMlb";

const DATA_DIR = join(__dirname, "..", "data");

function load(fileName: string): MlbRawGame[] {
  const { games } = JSON.parse(readFileSync(join(DATA_DIR, fileName), "utf8")) as { games: MlbRawGame[] };
  return games;
}

function score(g: MlbRawGame): number {
  const inputs: MlbRubricInputs = {
    finalMargin: g.finalMargin,
    totalRuns: g.totalRuns,
    largestDeficitOvercome: g.largestDeficitOvercome,
    walkOff: g.walkOff,
    extraInningsCount: g.extraInningsCount,
    combinedHomeRuns: g.combinedHomeRuns,
    maxHomeRunsByPlayer: g.maxHomeRunsByPlayer,
    teamBlanked: g.shutout,
    noHitter: g.noHitter,
    perfectGame: g.perfectGame,
    blownSave: g.blownSave,
    combinedErrors: g.combinedErrors,
  };
  return computeMlbWatchabilityScore(inputs, undefined).total;
}

const historicalSeasons: string[] = [];
for (let year = 2003; year <= 2023; year++) historicalSeasons.push(`mlbRawStats_${year}.json`);

const allGames = historicalSeasons.flatMap(load);
const qualifying = allGames.filter((g) => score(g) >= 90);
qualifying.sort((a, b) => score(b) - score(a));

console.log(`${qualifying.length} games clear the 90+ All-time bar across ${allGames.length} historical (2003-2023) games:`);
for (const g of qualifying) console.log(`  ${score(g)}  ${g.eventId}  ${g.away} @ ${g.home}  ${g.date.slice(0, 10)}`);

writeFileSync(join(DATA_DIR, "mlbHistoricalBarnBurners.json"), JSON.stringify({ games: qualifying }, null, 2), "utf8");
console.log(`\nWrote ${qualifying.length} games to mlbHistoricalBarnBurners.json`);
