// INVESTIGATION ONLY - not part of the build/server, not wired into
// migrateToGameStore.ts, writes nothing to gameStore/production. Scores
// every finished NBA 2023-24 game (the one season immediately missing from
// the app's current NBA backfill, which only has 2024-25/2025-26) through
// the exact same rubric.ts logic the live app uses, via the same
// mapEventToGame/computeWatchabilityScore functions the WNBA backfill
// (backfillHistoricalWatchabilityWnba.ts) already proved out for this
// exact "loop days, fetch scoreboard+summary, score, filter" pattern.
//
// Purpose: answer "what would a full 2023-24 backfill actually surface"
// before committing to writing it into gameStore for real - a short list
// of the highest-scoring real games, nothing persisted anywhere the app
// reads from.
//
// Run with: npx tsx src/investigateNba2023.ts
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { dateStringsBetween } from "./dateRange";
import { fetchScoreboard, fetchSummary } from "./espnClient";
import { mapEventToGame } from "./gameMapper";
import { computeWatchabilityScore, Tier, tierForScore } from "./rubric";

const DATA_DIR = join(__dirname, "..", "data");
const OUTPUT_PATH = join(DATA_DIR, "investigateNba2023.json");
const REQUEST_DELAY_MS = 320; // ~3 requests/sec

// 2023-24 regular season opened 2023-10-24; Celtics beat Mavericks in the
// Finals, closing out 2024-06-17. Window overshoots on both ends, same as
// every other backfill script in this codebase - ESPN just returns no
// events for the empty days.
const SEASON_WINDOW = { label: "2023-24", start: "2023-10-15", end: "2024-06-25" };

interface ScoredGame {
  eventId: string;
  date: string;
  away: string;
  home: string;
  awayScore: number;
  homeScore: number;
  finalMargin: number;
  score: number;
  tier: Tier;
}

interface OutputFile {
  generatedAt: string;
  games: ScoredGame[];
  completedDates: string[];
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function loadExisting(): OutputFile {
  if (!existsSync(OUTPUT_PATH)) return { generatedAt: new Date().toISOString(), games: [], completedDates: [] };
  try {
    return JSON.parse(readFileSync(OUTPUT_PATH, "utf8")) as OutputFile;
  } catch {
    return { generatedAt: new Date().toISOString(), games: [], completedDates: [] };
  }
}

function save(output: OutputFile): void {
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  output.generatedAt = new Date().toISOString();
  writeFileSync(OUTPUT_PATH, JSON.stringify(output, null, 2), "utf8");
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

async function main() {
  const output = loadExisting();
  const completedDates = new Set(output.completedDates);
  const gamesById = new Map(output.games.map((g) => [g.eventId, g]));

  const allDates = dateStringsBetween(SEASON_WINDOW.start, SEASON_WINDOW.end);
  const totalDates = allDates.length;
  let processedDates = 0;

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
        if (event.competitions[0]?.status.type.state !== "post") continue;

        const summary = await withRetries(() => fetchSummary(event.id, "nba"), `summary ${event.id}`);
        await sleep(REQUEST_DELAY_MS);
        if (!summary) continue;

        const mapped = mapEventToGame(event, "nba", summary);
        if (mapped.status !== "final" || mapped.rubric.finalMargin == null) continue;

        const breakdown = computeWatchabilityScore(mapped.rubric, undefined, "nba");
        const competition = event.competitions[0];
        const away = competition.competitors.find((c) => c.homeAway === "away")!;
        const home = competition.competitors.find((c) => c.homeAway === "home")!;

        gamesById.set(event.id, {
          eventId: event.id,
          date: mapped.tipoffUtc,
          away: mapped.away,
          home: mapped.home,
          awayScore: parseFloat(away.score),
          homeScore: parseFloat(home.score),
          finalMargin: mapped.rubric.finalMargin,
          score: breakdown.total,
          tier: tierForScore(breakdown.total),
        });
      }
    }

    completedDates.add(date);
    processedDates++;

    output.games = Array.from(gamesById.values());
    output.completedDates = Array.from(completedDates);
    save(output);

    if (processedDates % 20 === 0 || processedDates === totalDates) {
      console.log(`[${processedDates}/${totalDates} days] ${date} - ${output.games.length} games scored so far`);
    }
  }

  console.log(`\nDone. ${output.games.length} games scored for ${SEASON_WINDOW.label}.`);
  const barnBurners = output.games.filter((g) => g.score >= 70).sort((a, b) => b.score - a.score);
  console.log(`\n${barnBurners.length} games clear the 70+ "Barn Burner" bar:`);
  for (const g of barnBurners) {
    console.log(`  ${g.score.toFixed(0)}  ${g.away} @ ${g.home}  (${g.awayScore}-${g.homeScore})  ${g.date.slice(0, 10)}  [${g.tier}]`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
