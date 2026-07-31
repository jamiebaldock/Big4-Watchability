// Full per-game raw-stats backfill for every MLB season ESPN's box-score
// data reliably covers before the existing 2024/2025 files (backfillRawStatsMlb.ts/
// backfillRawStatsMlb2024.ts) - 2003 through 2023, 21 seasons. Same mapGame/
// MlbRawGame shape as those two scripts (reused, not reimplemented).
//
// 2003 is a real, tested lower bound, not a guess - checked directly against
// ESPN's actual API before writing this: the boxscore's batting.runs stat
// (what mapGame reads as the authoritative score) is present and correct in
// every 2003 game spot-checked (opening day, mid-season, September), but
// missing from every 2002 game checked the same way (would silently record
// every score as 0), and 2001-or-earlier seasons are missing the boxscore's
// stat groups entirely. This mirrors NBA's own tested 2002-03 boundary
// (investigateNbaBarnBurners.ts) almost exactly.
//
// A margin<=6 pre-filter (like NBA's Barn Burner scripts use) was considered
// and confirmed *safe* against the real 2024+2025 sample (4,951 games: every
// margin>6 game topped out at 59, well below even MLB's own Instant Classic
// bar of 60) - but deliberately NOT used here. Unlike basketball, baseball's
// margin distribution is flat enough that margin<=6 alone only excludes
// ~14% of real games, so the "cheap filter" barely reduces the expensive
// per-game summary-fetch volume - not worth the complexity and the sparser,
// cherry-picked-feeling per-season data a filtered version would produce.
// James's explicit call, 2026-07-30.
//
// SUPERSEDED 2026-07-31, one day later: the original plan above was to keep
// every one of these ~50k games live in gameStore as a full History archive
// for each older season. That shipped, immediately OOM-crashed production
// (see gameStore.ts's `statements` cache comment and
// migrateToGameStore.ts's runOnceEver/pruneOlderSeasonsExcept for the full
// story), and once James also decided to trim named-season chips down to
// 2024+ only, the "full archive per season" benefit stopped applying
// anyway - only the games that clear MLB's All-time bar are kept. This
// script's *output* (mlbRawStats_2003.json etc.) is now purely an
// intermediate, gitignored, local-only input to extractMlbBarnBurners.ts,
// not something migrated wholesale - see that script's own header for the
// standard shape this - and every future league's older-seasons backfill -
// should follow instead.
//
// One season at a time, in order, each with its own resumable
// completedDates state (own output file) - an interruption partway through
// only needs to resume the season in progress, not restart from 2003.
//
// Run with: npx tsx src/backfillRawStatsMlbHistorical.ts
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { dateStringsBetween } from "./dateRange";
import { mapGame, MlbRawGame } from "./backfillRawStatsMlb";

const DATA_DIR = join(__dirname, "..", "data");
const REQUEST_DELAY_MS = 320; // ~3 requests/sec, same pacing as every other backfill script
const BASE_PATH = "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb";

// Generous overshoot on both ends (ESPN just returns no events for the empty
// days, same convention every other backfill script in this codebase uses) -
// a uniform Feb 15 - Nov 15 window per year rather than hand-tuning each
// season's exact Opening Day/World Series-end date. Confirmed harmless even
// for 2020's COVID-shortened season (actual games late July - September) -
// it just means more empty-day scoreboard calls that cost nothing but a
// fast 0-event response.
const SEASON_LABELS = [
  "2003", "2004", "2005", "2006", "2007", "2008", "2009", "2010",
  "2011", "2012", "2013", "2014", "2015", "2016", "2017", "2018",
  "2019", "2020", "2021", "2022", "2023",
];

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

function outputPathFor(label: string): string {
  return join(DATA_DIR, `mlbRawStats_${label}.json`);
}

function loadExisting(label: string): OutputFile {
  const path = outputPathFor(label);
  if (!existsSync(path)) return { generatedAt: new Date().toISOString(), games: [], completedDates: [] };
  try {
    return JSON.parse(readFileSync(path, "utf8")) as OutputFile;
  } catch {
    return { generatedAt: new Date().toISOString(), games: [], completedDates: [] };
  }
}

function save(label: string, output: OutputFile): void {
  if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
  output.generatedAt = new Date().toISOString();
  writeFileSync(outputPathFor(label), JSON.stringify(output, null, 2), "utf8");
}

async function fetchScoreboard(yyyymmdd: string): Promise<EspnScoreboardEvent[]> {
  const data = await getJson<{ events: EspnScoreboardEvent[] }>(`${BASE_PATH}/scoreboard?dates=${yyyymmdd}`);
  return data.events ?? [];
}

async function fetchSummary(eventId: string): Promise<Parameters<typeof mapGame>[3]> {
  return getJson<Parameters<typeof mapGame>[3]>(`${BASE_PATH}/summary?event=${eventId}`);
}

async function backfillSeason(label: string): Promise<number> {
  const output = loadExisting(label);
  const completedDates = new Set(output.completedDates);
  const gamesById = new Map(output.games.map((g) => [g.eventId, g]));

  const start = `${label}-02-15`;
  const end = `${label}-11-15`;
  const allDates = dateStringsBetween(start, end);
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

        const mapped = mapGame(event.id, label, event.date, summary);
        if (mapped) gamesById.set(event.id, mapped);
      }
    }

    completedDates.add(date);
    processedDates++;

    output.games = Array.from(gamesById.values());
    output.completedDates = Array.from(completedDates);
    save(label, output);

    if (processedDates % 20 === 0 || processedDates === totalDates) {
      console.log(`  [${label}: ${processedDates}/${totalDates} days] ${date} - ${output.games.length} games collected so far`);
    }
  }

  return output.games.length;
}

async function main() {
  console.log(`Backfilling ${SEASON_LABELS.length} MLB seasons: ${SEASON_LABELS[0]}-${SEASON_LABELS[SEASON_LABELS.length - 1]}`);
  let grandTotal = 0;
  for (const label of SEASON_LABELS) {
    // Skip a season whose file already looks complete (every date in its
    // window already marked done) - lets this whole script be safely
    // re-run after an interruption without redoing finished seasons.
    const existing = loadExisting(label);
    const expectedDates = dateStringsBetween(`${label}-02-15`, `${label}-11-15`).length;
    if (existing.completedDates.length >= expectedDates) {
      console.log(`=== ${label}: already complete (${existing.games.length} games) - skipping ===`);
      grandTotal += existing.games.length;
      continue;
    }

    console.log(`=== ${label} ===`);
    const count = await backfillSeason(label);
    console.log(`=== ${label} done: ${count} games ===\n`);
    grandTotal += count;
  }
  console.log(`\nAll seasons done. ${grandTotal} total games collected across ${SEASON_LABELS.length} seasons.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
