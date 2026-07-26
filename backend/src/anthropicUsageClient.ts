// Claude API cost tracking for the Admin page - Anthropic's Usage & Cost
// Admin API (platform.claude.com/docs/en/api/usage-cost-api), gated on a
// separate ANTHROPIC_ADMIN_KEY env var - deliberately NOT the same
// ANTHROPIC_API_KEY llm.ts uses for actual completions. Anthropic's Admin
// API requires a distinct Admin key (sk-ant-admin01-...), only issuable
// from an Organization's Console settings - individual accounts can't
// generate one at all (Anthropic's own docs: "The Admin API is unavailable
// for individual accounts"). Same degrade-to-null-when-unset pattern as
// renderClient.ts/fcm.ts/youtubeClient.ts for every other optional secret
// in this codebase.
const ANTHROPIC_COST_URL = "https://api.anthropic.com/v1/organizations/cost_report";
const ANTHROPIC_API_VERSION = "2023-06-01";

function getAdminKey(): string | undefined {
  return process.env.ANTHROPIC_ADMIN_KEY;
}

export function isAnthropicUsageConfigured(): boolean {
  return Boolean(getAdminKey());
}

export interface AnthropicUsage {
  configured: boolean;
  last7DaysCostUsd?: number;
  error?: string;
}

interface CostReportResultItem {
  amount?: string;
  currency?: string;
}

interface CostReportBucket {
  results?: CostReportResultItem[];
}

interface CostReportResponse {
  data?: CostReportBucket[];
}

/**
 * Trailing 7-day cost total in USD, summed across every bucket/result the
 * report returns - the Cost API reports amounts as decimal-string cents
 * (Anthropic's own docs: "reported as decimal strings in lowest units
 * (cents)"), so each result is parsed and divided by 100 before summing.
 * Never throws - a bad/missing key or network failure surfaces as
 * { configured: true, error: ... }, same reasoning as renderClient.ts.
 */
export async function getAnthropicUsage(): Promise<AnthropicUsage> {
  const apiKey = getAdminKey();
  if (!apiKey) return { configured: false };

  const endingAt = new Date();
  const startingAt = new Date(endingAt.getTime() - 7 * 24 * 60 * 60 * 1000);
  const params = new URLSearchParams({
    starting_at: startingAt.toISOString(),
    ending_at: endingAt.toISOString(),
  });

  try {
    const res = await fetch(`${ANTHROPIC_COST_URL}?${params.toString()}`, {
      headers: {
        "anthropic-version": ANTHROPIC_API_VERSION,
        "x-api-key": apiKey,
      },
    });

    if (!res.ok) {
      return { configured: true, error: `Anthropic cost API returned ${res.status}` };
    }

    const data = (await res.json()) as CostReportResponse;
    let totalCents = 0;
    for (const bucket of data.data ?? []) {
      for (const result of bucket.results ?? []) {
        const amount = parseFloat(result.amount ?? "0");
        if (Number.isFinite(amount)) totalCents += amount;
      }
    }

    return { configured: true, last7DaysCostUsd: totalCents / 100 };
  } catch (err) {
    return { configured: true, error: err instanceof Error ? err.message : "Anthropic cost API request failed" };
  }
}
