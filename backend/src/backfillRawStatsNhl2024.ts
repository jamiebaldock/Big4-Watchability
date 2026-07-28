// One-off analysis script, same shape as backfillRawStatsNhl.ts (that
// file's own header comment explains the general approach/data source) -
// this is the 2024-25 NHL season specifically, added to History per
// James's ask, kept as its own file/output rather than widening the
// 2025-26 script's SEASON_WINDOW so re-running either script independently
// never risks clobbering the other season's already-collected data or its
// own completedDates resume-state.
//
// 2024-25 regular season opened 2024-10-04; the Stanley Cup Final (Florida
// Panthers over Edmonton Oilers) closed out with Game 6 on 2025-06-17 -
// window overshoots on both ends the same way the 2025-26 script's does.
//
// Run with: npx tsx src/backfillRawStatsNhl2024.ts
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { dateStringsBetween } from "./dateRange";
import { mapGame, NhlRawGame } from "./backfillRawStatsNhl";

const DATA_DIR = join(__dirname, "..", "data");
const OUTPUT_PATH = join(DATA_DIR, "nhlRawStats2024.json");
const REQUEST_DELAY_MS = 320; // ~3 requests/sec, same pacing as the 2025-26 script
const BASE_PATH = "https://site.api.espn.com/apis/site/v2/sports/hockey/nhl";
const SEASON_WINDOW = { label: "2024-25", start: "2024-09-20", end: "2025-06-25" };

interface EspnScoreboardEvent {
  id: string;
  date: string;
  season?: { type: number; slug: string };
  competitions: Array<{
    status: { type: { state: string } };
    notes?: Array<{ type: string; headline: string }>;
  }>;
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
  games: NhlRawGame[];
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

function derivePlayoffRoundLabel(notes: Array<{ type: string; headline: string }> | undefined): string | undefined {
  const headline = notes?.[0]?.headline;
  if (!headline) return undefined;
  return headline.replace(/\s*-\s*Game\s*\d+\s*$/i, "").trim();
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
        if (event.season?.slug === "preseason") continue; // preseason excluded, same rule as the 2025-26 script
        if (event.competitions[0]?.status.type.state !== "post") continue;

        const summary = await withRetries(() => fetchSummary(event.id), `summary ${event.id}`);
        await sleep(REQUEST_DELAY_MS);
        if (!summary) continue;

        const playoffRoundLabel = event.season?.type === 3 ? derivePlayoffRoundLabel(event.competitions[0]?.notes) : undefined;
        const mapped = mapGame(event.id, SEASON_WINDOW.label, event.date, summary, event.season?.type ?? 2, playoffRoundLabel);
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
