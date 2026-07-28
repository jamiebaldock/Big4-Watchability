// One-off analysis script, same shape as backfillRawStatsNfl.ts (that
// file's own header comment explains the general approach/data source) -
// this is the 2024 NFL season specifically, added to History per James's
// ask, kept as its own file/output rather than widening the 2025 script's
// SEASON_WINDOW so re-running either script independently (e.g. if next
// season needs the same treatment later) never risks clobbering the other
// season's already-collected data or its own completedDates resume-state.
//
// 2024 regular season opened 2024-09-05; Super Bowl LIX (Eagles 40, Chiefs
// 22) was played 2025-02-09 - window overshoots on both ends the same way
// the 2025 script's does.
//
// Run with: npx tsx src/backfillRawStatsNfl2024.ts
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { dateStringsBetween } from "./dateRange";
import { mapGame, NflRawGame } from "./backfillRawStatsNfl";

const DATA_DIR = join(__dirname, "..", "data");
const OUTPUT_PATH = join(DATA_DIR, "nflRawStats2024.json");
const REQUEST_DELAY_MS = 320; // ~3 requests/sec, same pacing as the 2025 script
const BASE_PATH = "https://site.api.espn.com/apis/site/v2/sports/football/nfl";
const SEASON_WINDOW = { label: "2024", start: "2024-08-25", end: "2025-02-15" };

interface EspnScoreboardEvent {
  id: string;
  date: string;
  season?: { type: number; slug: string };
  week?: { number: number };
  competitions: Array<{ status: { type: { state: string } } }>;
}

interface EspnSummaryHeader {
  competitions: Array<{ status: { type: { completed: boolean } } }>;
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

interface OutputFile {
  generatedAt: string;
  games: NflRawGame[];
  completedDates: string[];
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

async function fetchScoreboard(yyyymmdd: string): Promise<EspnScoreboardEvent[]> {
  const data = await getJson<{ events: EspnScoreboardEvent[] }>(`${BASE_PATH}/scoreboard?dates=${yyyymmdd}`);
  return data.events ?? [];
}

async function fetchSummary(eventId: string): Promise<Parameters<typeof mapGame>[3]> {
  return getJson<Parameters<typeof mapGame>[3]>(`${BASE_PATH}/summary?event=${eventId}`);
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
    const events = await withRetries(() => fetchScoreboard(yyyymmdd), `scoreboard ${date}`);
    await sleep(REQUEST_DELAY_MS);

    if (events) {
      for (const event of events) {
        if (event.season?.type === 1) continue; // preseason excluded, same rule as the 2025 script
        if (event.competitions[0]?.status.type.state !== "post") continue;

        const summary = await withRetries(() => fetchSummary(event.id), `summary ${event.id}`);
        await sleep(REQUEST_DELAY_MS);
        if (!summary) continue;

        const mapped = mapGame(event.id, SEASON_WINDOW.label, event.date, summary, event.season?.type ?? 2, event.week?.number);
        if (mapped) gamesById.set(event.id, mapped);
      }
    }

    completedDates.add(date);
    processedDates++;

    output.games = Array.from(gamesById.values());
    output.completedDates = Array.from(completedDates);
    save(output);

    if (processedDates % 10 === 0 || processedDates === totalDates) {
      console.log(`[${processedDates}/${totalDates} days] ${date} - ${output.games.length} games collected so far`);
    }
  }

  console.log(`\nDone. ${output.games.length} games collected for ${SEASON_WINDOW.label}.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
