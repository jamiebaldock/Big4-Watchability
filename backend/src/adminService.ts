// Backs the mobile app's hidden Admin page - a pre-launch, James-only
// operational view into the highlights-search pipeline (built after
// investigating why recent games weren't reliably getting highlights; see
// that investigation's findings for the two real bugs found - a too-tight
// retry window and an MLB team-nickname mismatch - which this page exists
// to make visible without needing another one-off diagnostic route next time).
//
// PIN check is server-side, not client-side, deliberately: a client-side-
// only check would ship the PIN inside the APK, trivially recoverable by
// decompiling it once this is on the Play Store. Real login can later
// replace exactly the pin/token issuance below without touching how the
// client calls the other endpoints - they already only care about a bearer
// token, not how it was obtained.
import { randomBytes } from "node:crypto";
import { AlertDeliveryStats, getAlertDeliveryStats, getDeviceFcmToken } from "./alertStore";
import { AnthropicUsage, getAnthropicUsage } from "./anthropicUsageClient";
import { DEAD_TOKEN_CODES, sendPush } from "./fcm";
import {
  DAILY_SEARCH_BUDGET,
  GameRow,
  LagPercentiles,
  canSpendSearchQuota,
  getFinalGamesMissingHighlights,
  getFinalMlbGamesMissingHighlights,
  getGame,
  getLagPercentiles,
  getSearchBudgetHistory,
  getSearchOutcomeCounts,
  getTodaySearchBudgetCount,
  recordHighlightsSearchLog,
  recordSearchQuotaSpend,
  setHighlights,
} from "./gameStore";
import { getGamesForDateAnySport } from "./httpHandler";
import { RenderStatus, getRenderStatus } from "./renderClient";
import { LeagueGroup } from "./types";
import { HighlightsLeague, searchHighlightsVideo } from "./youtubeClient";

export class AdminUnauthorizedError extends Error {}
export class AdminBadRequestError extends Error {}

// In-memory only - a Render restart (deploy, or the free tier spinning down
// an idle instance) invalidates every outstanding session, which just means
// re-entering the PIN once. No persistence needed for a single-operator,
// low-frequency admin page; not worth a DB table for this.
const ADMIN_TOKEN_TTL_MS = 24 * 60 * 60 * 1000;
const tokens = new Map<string, number>();

export function adminLogin(pin: string): { token: string } {
  const expected = process.env.ADMIN_PIN;
  if (!expected) throw new AdminBadRequestError("ADMIN_PIN is not configured on the server");
  if (pin !== expected) throw new AdminUnauthorizedError("incorrect PIN");

  const token = randomBytes(24).toString("hex");
  tokens.set(token, Date.now() + ADMIN_TOKEN_TTL_MS);
  return { token };
}

export function isValidAdminToken(token: string | undefined): boolean {
  if (!token) return false;
  const expiry = tokens.get(token);
  if (!expiry || expiry < Date.now()) {
    tokens.delete(token);
    return false;
  }
  return true;
}

export interface AdminStats {
  todayCount: number;
  dailyCap: number;
  budgetHistory: { date: string; count: number }[];
  lagPercentiles: Record<string, LagPercentiles>;
  outcomeCounts: Record<string, number>;
  pushStats: AlertDeliveryStats;
  renderStatus: RenderStatus;
  anthropicUsage: AnthropicUsage;
}

/**
 * Async (unlike the DB-only queries it started as) - renderStatus and
 * anthropicUsage each make a real outbound API call. Both run alongside the
 * existing DB reads via Promise.all rather than serially, and both degrade
 * to { configured: false } with zero added latency when their own env var
 * isn't set (renderClient.ts/anthropicUsageClient.ts's own doc comments),
 * so this stays fast for anyone who hasn't wired those up yet. Acceptable
 * to add real network latency here at all only because this is a low-
 * frequency, single-operator admin page, not a hot path.
 */
export async function getAdminStats(): Promise<AdminStats> {
  const [renderStatus, anthropicUsage] = await Promise.all([getRenderStatus(), getAnthropicUsage()]);
  return {
    todayCount: getTodaySearchBudgetCount(),
    dailyCap: DAILY_SEARCH_BUDGET,
    budgetHistory: getSearchBudgetHistory(14),
    // Basketball/MLB only - the three leagues with highlights search
    // actually wired in live (NFL/NHL's own search is built but dormant,
    // see nflGamesService.ts/nhlGamesService.ts).
    lagPercentiles: {
      nba: getLagPercentiles("nba", "nba"),
      wnba: getLagPercentiles("wnba", "wnba"),
      mlb: getLagPercentiles("mlb", "mlb"),
    },
    outcomeCounts: getSearchOutcomeCounts(7),
    pushStats: getAlertDeliveryStats(7),
    renderStatus,
    anthropicUsage,
  };
}

export interface AdminMissingHighlightsGame {
  eventId: string;
  league: string;
  leagueGroup: string;
  away: string;
  home: string;
  tipoffUtc: string;
  ytCheckCount: number;
  ytLastCheckedAt: string | null;
}

function toAdminRow(row: GameRow): AdminMissingHighlightsGame {
  return {
    eventId: row.eventId,
    league: row.league,
    leagueGroup: row.leagueGroup,
    away: row.away,
    home: row.home,
    tipoffUtc: row.tipoffUtc,
    ytCheckCount: row.ytCheckCount,
    ytLastCheckedAt: row.ytLastCheckedAt,
  };
}

/** Every currently-missing recent game across every league with live search - newest first, same as the underlying gameStore queries. */
export function getAdminMissingHighlights(): AdminMissingHighlightsGame[] {
  return [...getFinalGamesMissingHighlights(), ...getFinalMlbGamesMissingHighlights()]
    .sort((a, b) => (a.tipoffUtc < b.tipoffUtc ? 1 : -1))
    .map(toAdminRow);
}

const SUPPORTED_RESEND_LEAGUES: ReadonlySet<string> = new Set(["nba", "wnba", "mlb"]);

export interface AdminResendResult {
  matched: boolean;
  videoId?: string;
  title?: string;
}

/**
 * Manual, on-demand re-search for one game - the Admin page's "Re-search"
 * button. Deliberately bypasses the normal scheduling gates (the 15/45-min
 * timing window, MAX_HIGHLIGHTS_CHECKS's 2-attempt abandonment) since the
 * whole point is retrying a game that path already gave up on. Still spends
 * a real search.list unit against the same shared daily budget every other
 * caller uses - there's only one real quota, Google's, and this can't
 * bypass that even if it bypasses this app's own internal scheduling.
 */
export async function resendHighlightsSearch(eventId: string): Promise<AdminResendResult> {
  const row = getGame(eventId);
  if (!row) throw new AdminBadRequestError("no such game");
  if (!SUPPORTED_RESEND_LEAGUES.has(row.leagueGroup)) {
    throw new AdminBadRequestError(`highlights search isn't live for ${row.leagueGroup} yet`);
  }
  if (!canSpendSearchQuota()) {
    throw new AdminBadRequestError("today's search quota is already spent");
  }

  const league = row.leagueGroup as HighlightsLeague;
  recordSearchQuotaSpend();

  let match;
  try {
    match = await searchHighlightsVideo(league, row.away, row.home, row.tipoffUtc);
  } catch (err) {
    recordHighlightsSearchLog(row.eventId, row.leagueGroup, "api_error", String(err));
    throw err;
  }

  if (match) {
    setHighlights(row.eventId, match.videoId, match.publishedAt);
    recordHighlightsSearchLog(row.eventId, row.leagueGroup, "matched");
    return { matched: true, videoId: match.videoId, title: match.title };
  }
  recordHighlightsSearchLog(row.eventId, row.leagueGroup, "no_match");
  return { matched: false };
}

const TEST_PUSH_LEAGUE_ORDER: LeagueGroup[] = ["nba", "wnba", "mlb", "nfl", "nhl"];

export interface AdminTestPushResult {
  sent: boolean;
  eventId?: string;
  away?: string;
  home?: string;
  lg?: string;
}

/**
 * The Admin page's "send test push" button - lets James verify the whole
 * tap-to-deep-link path (AlertsFirebaseMessagingService -> DeepLinkViewModel
 * -> AppRoot's jumpToDate) on demand, without waiting for a real close-swing
 * game. Reuses alertsPoller.ts's own notifyDevice payload shape exactly
 * (title/body/eventId/lg/utc) so this is a genuine dry run of the real path,
 * not a separate one-off. Targets [deviceId] specifically (the calling
 * device's own alert registration, sent up by the mobile Admin screen) -
 * not a fan-out - since this button exists for one operator to test their
 * own phone, not to alert every real registered device.
 */
export async function sendAdminTestPush(deviceId: string): Promise<AdminTestPushResult> {
  const fcmToken = getDeviceFcmToken(deviceId);
  if (!fcmToken) {
    throw new AdminBadRequestError(
      "this device has no registered push token - open Settings > Alerts once first so it registers"
    );
  }

  // Any real, currently-scheduled game works as the deep-link target - the
  // point is exercising the tap -> jump-to-day path with genuine
  // eventId/lg/utc values the schedule actually has, not a synthetic one
  // GamesTab could never find. Todays date, first league (in fixed order)
  // that actually has at least one game.
  const today = new Date().toISOString().slice(0, 10);
  let target: { id?: string; a: string; h: string; lg: string; utc: string } | undefined;
  for (const leagueGroup of TEST_PUSH_LEAGUE_ORDER) {
    const games = await getGamesForDateAnySport(today, leagueGroup);
    if (games.length > 0) {
      target = games[0];
      break;
    }
  }
  if (!target?.id) {
    throw new AdminBadRequestError("no games scheduled today in any league to use as a test target");
  }

  const results = await sendPush([fcmToken], {
    title: `${target.a} @ ${target.h}`,
    body: "Test push - tap to verify deep-linking.",
    eventId: target.id,
    lg: target.lg,
    utc: target.utc,
  });
  const result = results[0];
  if (!result.ok) {
    if (result.errorCode && DEAD_TOKEN_CODES.has(result.errorCode)) {
      throw new AdminBadRequestError("this device's push token is no longer valid - reopen Settings > Alerts to re-register");
    }
    throw new AdminBadRequestError(`push send failed: ${result.errorCode ?? "unknown error"}`);
  }

  return { sent: true, eventId: target.id, away: target.a, home: target.h, lg: target.lg };
}
