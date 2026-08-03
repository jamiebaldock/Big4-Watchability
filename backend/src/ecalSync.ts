// Sync official league e-calendars against gameStore to catch/correct
// schedule discrepancies (e.g., tipoff time changes, official corrections)
// that may differ from ESPN's data. Official e-calendars are the source of
// truth for game dates/times; ESPN remains primary for richer metadata
// (teams, preview, play-by-play).
//
// Fetches three official ICS feeds (NBA, NHL, MLB), parses events, compares
// against gameStore by (league, date, teams), and updates tipoff_utc if the
// official source differs from what's stored. Idempotent - safe to run on
// every boot or on a scheduled cadence.

import https from "node:https";
import { AnyLeague, getGameByLeagueAndTeamsAndDate, updateTipoffTime } from "./gameStore";

// Official e-calendar ICS feed URLs (webcal:// converted to https://)
// Only NBA, NHL, MLB have official feeds; NFL and WNBA don't provide them (yet).
const ECAL_FEEDS: Partial<Record<AnyLeague, string>> = {
  nba: "https://ics.ecal.com/ecal-sub/6a706e928fae7f0002264920/NBA.ics",
  nhl: "https://ics.ecal.com/ecal-sub/6a7071cf4f668a0002efec10/NHL.ics",
  mlb: "https://ics.ecal.com/ecal-sub/6a70728b4f668a0002efec1b/MLB%20.ics",
};

interface IcsEvent {
  summary?: string;
  dtstart?: { toJSDate?(): Date; toUnixTime?(): number } | string | Date;
  dtend?: { toJSDate?(): Date; toUnixTime?(): number } | string | Date;
  location?: string;
  description?: string;
}

interface ParsedGame {
  league: AnyLeague;
  awayTeam: string;
  homeTeam: string;
  tipoffUtc: string; // ISO 8601
}

/**
 * Parse an ICS event summary to extract team names.
 * Expected format: "Away Team @ Home Team" or "Away Team vs Home Team"
 * Returns [awayTeam, homeTeam] or null if parsing fails.
 */
function parseTeamsFromSummary(summary?: string): [string, string] | null {
  if (!summary) return null;

  // Try both @ and vs separators
  const separatorPatterns = [/^(.+?)\s+@\s+(.+)$/, /^(.+?)\s+vs\.?\s+(.+)$/i];

  for (const pattern of separatorPatterns) {
    const match = summary.match(pattern);
    if (match) {
      return [match[1].trim(), match[2].trim()];
    }
  }

  return null;
}

/**
 * Convert an ICS date to ISO 8601 UTC string.
 * Handles both Date objects and ICS date-time objects.
 */
function dateToUtcIso(dt: unknown): string | null {
  if (!dt) return null;

  let jsDate: Date | null = null;

  if (dt instanceof Date) {
    jsDate = dt;
  } else if (typeof dt === "object" && dt !== null) {
    // ICS date-time object (from ical library)
    if ("toJSDate" in dt && typeof dt.toJSDate === "function") {
      jsDate = (dt as any).toJSDate();
    }
  } else if (typeof dt === "string") {
    // Try parsing as ISO string
    jsDate = new Date(dt);
  }

  if (!jsDate || isNaN(jsDate.getTime())) return null;

  return jsDate.toISOString();
}

/**
 * Fetch and parse a single e-calendar ICS feed.
 * Returns array of parsed games with tipoff times.
 */
async function fetchAndParseEcal(league: AnyLeague): Promise<ParsedGame[]> {
  const feedUrl = ECAL_FEEDS[league];
  if (!feedUrl) {
    console.error(`No e-calendar feed configured for league ${league}`);
    return [];
  }

  return new Promise((resolve, reject) => {
    https
      .get(feedUrl, (res) => {
        let data = "";

        res.on("data", (chunk) => {
          data += chunk;
        });

        res.on("end", () => {
          try {
            const games = parseIcsData(league, data);
            resolve(games);
          } catch (err) {
            console.error(`Failed to parse ICS for ${league}:`, err);
            reject(err);
          }
        });
      })
      .on("error", (err) => {
        console.error(`Failed to fetch e-calendar for ${league}:`, err);
        reject(err);
      });
  });
}

/**
 * Parse raw ICS data (text) and extract game events.
 * Simple line-by-line parser for the fields we need (SUMMARY, DTSTART).
 */
function parseIcsData(league: AnyLeague, icsText: string): ParsedGame[] {
  const games: ParsedGame[] = [];
  const lines = icsText.split(/\r?\n/);

  let currentEvent: { summary?: string; dtstart?: string } = {};

  for (const line of lines) {
    if (line.startsWith("BEGIN:VEVENT")) {
      currentEvent = {};
    } else if (line.startsWith("SUMMARY:")) {
      currentEvent.summary = line.slice("SUMMARY:".length).trim();
    } else if (line.startsWith("DTSTART")) {
      // Extract the date/time value (format: DTSTART:20261003T110000Z or DTSTART;TZID=....:20261003T110000)
      const match = line.match(/DTSTART(?:;[^:]*)?:(.+)/);
      if (match) {
        currentEvent.dtstart = match[1].trim();
      }
    } else if (line.startsWith("END:VEVENT")) {
      // Try to extract game info from current event
      if (currentEvent.summary && currentEvent.dtstart) {
        const teams = parseTeamsFromSummary(currentEvent.summary);
        const tipoffUtc = formatIcsDateTime(currentEvent.dtstart);

        if (teams && tipoffUtc) {
          games.push({
            league,
            awayTeam: teams[0],
            homeTeam: teams[1],
            tipoffUtc,
          });
        }
      }
      currentEvent = {};
    }
  }

  return games;
}

/**
 * Convert ICS date-time string to ISO 8601 UTC.
 * Handles both UTC (Z suffix) and local time (no timezone info).
 * ICS format: 20261003T110000Z or 20261003T110000
 */
function formatIcsDateTime(icsDatetime: string): string | null {
  const icsDateTimePattern = /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z)?$/;
  const match = icsDatetime.match(icsDateTimePattern);

  if (!match) return null;

  const [, year, month, day, hour, minute, second, isUtc] = match;

  // Construct a Date - if Z suffix is present, it's UTC; otherwise treat as UTC
  // (ICS feeds from ecal.com should always provide timezone-aware times)
  const dateString = `${year}-${month}-${day}T${hour}:${minute}:${second}${isUtc ? "Z" : "Z"}`;
  const jsDate = new Date(dateString);

  if (isNaN(jsDate.getTime())) return null;

  return jsDate.toISOString();
}

/**
 * Sync a league's official e-calendar against gameStore.
 * Fetches official games, compares against stored games, updates tipoff times if needed.
 */
async function syncLeagueEcal(league: AnyLeague): Promise<{ checked: number; updated: number }> {
  console.log(`[ecalSync] Syncing ${league} e-calendar...`);

  try {
    const ecalGames = await fetchAndParseEcal(league);
    let updated = 0;

    for (const ecalGame of ecalGames) {
      const stored = getGameByLeagueAndTeamsAndDate(league, ecalGame.awayTeam, ecalGame.homeTeam, ecalGame.tipoffUtc);

      if (stored) {
        // Game exists - check if tipoff time differs
        if (stored.tipoff_utc !== ecalGame.tipoffUtc) {
          console.log(
            `[ecalSync] ${league} tipoff mismatch: ` +
              `${ecalGame.awayTeam} @ ${ecalGame.homeTeam} ` +
              `stored=${stored.tipoff_utc}, official=${ecalGame.tipoffUtc}`,
          );

          updateTipoffTime(stored.event_id, ecalGame.tipoffUtc);
          updated++;
        }
      } else {
        // Game not yet in store - this shouldn't happen in normal operation
        // (ESPN's poller should have fetched it first), so log but don't insert
        console.log(
          `[ecalSync] ${league} game in official e-calendar but not yet in gameStore: ` +
            `${ecalGame.awayTeam} @ ${ecalGame.homeTeam} ${ecalGame.tipoffUtc}`,
        );
      }
    }

    console.log(`[ecalSync] ${league}: checked ${ecalGames.length} games, updated ${updated} tipoff times`);
    return { checked: ecalGames.length, updated };
  } catch (err) {
    console.error(`[ecalSync] Failed to sync ${league}:`, err);
    return { checked: 0, updated: 0 };
  }
}

/**
 * Sync all available official e-calendars.
 * Returns summary of checked/updated games by league.
 */
export async function syncAllEcals(): Promise<Record<string, { checked: number; updated: number }>> {
  const results: Record<string, { checked: number; updated: number }> = {};

  for (const league of Object.keys(ECAL_FEEDS) as AnyLeague[]) {
    results[league] = await syncLeagueEcal(league);
  }

  return results;
}
