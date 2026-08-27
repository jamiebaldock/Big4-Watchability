// Shared by espnClient.ts / mlbEspnClient.ts / nflEspnClient.ts /
// nhlEspnClient.ts - each had its own near-identical getJson with no headers
// and no retry, which is exactly what let a single ESPN scoreboard-endpoint
// block (2026-08-27, confirmed via Render logs as a 403 from
// site.api.espn.com, cleared by a service restart rotating Render's Starter-
// plan outbound IP - see BACKLOG.md) take down every league's live schedule
// at once with zero chance to recover mid-request. A real browser User-Agent
// plus a short retry specifically on 403/429/5xx gives a transient block a
// chance to clear within one request instead of failing instantly every
// time - it does not fix ESPN blocking an IP outright (nothing server-side
// code can do about that), only the "one blip = every request in flight
// fails" part.
const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36";

const RETRYABLE_STATUSES = new Set([403, 429, 502, 503, 504]);
const RETRY_DELAYS_MS = [500, 1500];

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * [label] is the per-sport prefix each client's own error messages already
 * used (e.g. "NHL" -> "ESPN NHL request failed: ...") - passed through
 * unchanged so log lines already grepped for elsewhere (alertsPoller.ts's
 * own catch blocks) keep matching. Omit it for espnClient.ts's generic
 * (NBA/WNBA) requests, which never had a league name in the message.
 */
export async function fetchEspnJson<T>(url: string, label = ""): Promise<T> {
  const prefix = label ? `ESPN ${label} request` : "ESPN request";
  let lastError: Error = new Error(`${prefix} failed for an unknown reason (${url})`);

  for (let attempt = 0; attempt <= RETRY_DELAYS_MS.length; attempt++) {
    const res = await fetch(url, {
      headers: { "User-Agent": USER_AGENT, Accept: "application/json" }
    });
    if (res.ok) return (await res.json()) as T;

    lastError = new Error(`${prefix} failed: ${res.status} ${res.statusText} (${url})`);
    if (!RETRYABLE_STATUSES.has(res.status) || attempt === RETRY_DELAYS_MS.length) {
      throw lastError;
    }
    await sleep(RETRY_DELAYS_MS[attempt]);
  }

  throw lastError;
}
