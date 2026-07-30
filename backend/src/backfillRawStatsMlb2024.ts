// One-off analysis script, same shape as backfillRawStatsMlb.ts (that
// file's own header comment explains the general approach/data source) -
// this is the 2024 MLB season specifically, added to History per James's
// ask (bringing MLB into line with NFL/NHL, which both already have "this
// season" + 2 full past-season tabs + All Time). Kept as its own file/
// output rather than widening the 2025 script's SEASON_WINDOW so
// re-running either script independently never risks clobbering the
// other season's already-collected data or its own completedDates
// resume-state - same reasoning as backfillRawStatsNfl2024.ts/
// backfillRawStatsNhl2024.ts.
//
// 2024 regular season opened 2024-03-20 (Dodgers-Padres in Seoul; most
// teams 2024-03-28); World Series Game 5 (Dodgers over Yankees) was played
// 2024-10-30 - window overshoots on both ends the same way the 2025
// script's does.
//
// Run with: npx tsx src/backfillRawStatsMlb2024.ts
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { dateStringsBetween } from "./dateRange";
import { mapGame, MlbRawGame } from "./backfillRawStatsMlb";

const DATA_DIR = join(__dirname, "..", "data");
const OUTPUT_PATH = join(DATA_DIR, "mlbRawStats2024.json");
const REQUEST_DELAY_MS = 320; // ~3 requests/sec, same pacing as the 2025 script
const BASE_PATH = "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb";
const SEASON_WINDOW = { label: "2024", start: "2024-02-15", end: "2024-11-15" };

interface EspnScoreboardEvent {
  id: string;
  date: string;
  season?: { type: number; slug: string };
  competitions: Array<{ status: { type: { state: string } } }>;
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
  games: MlbRawGame[];
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
        if (event.season?.slug === "preseason" || event.season?.type === 1) continue;
        if (event.season?.slug === "off-season") continue;
        if (event.competitions[0]?.status.type.state !== "post") continue;

        const summary = await withRetries(() => fetchSummary(event.id), `summary ${event.id}`);
        await sleep(REQUEST_DELAY_MS);
        if (!summary) continue;

        const mapped = mapGame(event.id, SEASON_WINDOW.label, event.date, summary);
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
