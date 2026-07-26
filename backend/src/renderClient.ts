// Backend service health for the Admin page - Render's own REST API
// (api.render.com/v1), gated on a RENDER_API_KEY env var the same
// degrade-to-null-when-unset pattern as fcm.ts/youtubeClient.ts use for
// their own optional secrets: the app must keep working fully without this
// configured, just with the corresponding Admin section showing "not
// configured yet" instead of real data.
//
// SERVICE_ID is this specific deployment's own Render service id (visible
// on the Render dashboard's service page, "Service ID: srv-..."), hardcoded
// rather than env-configured - this is a single, fixed personal deployment
// (not a multi-tenant app that would ever need a different id), same
// reasoning as youtubeClient.ts's hardcoded per-league channel ids.
const RENDER_SERVICE_ID = "srv-d97g5e0k1i2s73e2a460";
const RENDER_API_BASE = "https://api.render.com/v1";

function getApiKey(): string | undefined {
  return process.env.RENDER_API_KEY;
}

export function isRenderConfigured(): boolean {
  return Boolean(getApiKey());
}

export interface RenderStatus {
  configured: boolean;
  serviceStatus?: string;
  lastDeployStatus?: string;
  lastDeployAt?: string;
  error?: string;
}

interface RenderServiceResponse {
  service?: { suspended?: string; suspenders?: string[] };
  suspended?: string;
}

interface RenderDeployListItem {
  deploy?: { status?: string; finishedAt?: string | null; createdAt?: string };
}

/**
 * One Render API call for service state + one for the most recent deploy -
 * both real, live reads (not cached), since this only ever fires when the
 * Admin page is open, a low-frequency, single-operator surface (same
 * reasoning as every other admin-only query in this codebase). Never
 * throws: a network failure or bad key surfaces as { configured: true,
 * error: ... } so the Admin page can show a real error message instead of
 * a broken dashboard.
 */
export async function getRenderStatus(): Promise<RenderStatus> {
  const apiKey = getApiKey();
  if (!apiKey) return { configured: false };

  const headers = { Authorization: `Bearer ${apiKey}` };

  try {
    const [serviceRes, deploysRes] = await Promise.all([
      fetch(`${RENDER_API_BASE}/services/${RENDER_SERVICE_ID}`, { headers }),
      fetch(`${RENDER_API_BASE}/services/${RENDER_SERVICE_ID}/deploys?limit=1`, { headers }),
    ]);

    if (!serviceRes.ok || !deploysRes.ok) {
      return { configured: true, error: `Render API returned ${serviceRes.status}/${deploysRes.status}` };
    }

    const service = (await serviceRes.json()) as RenderServiceResponse;
    const deploys = (await deploysRes.json()) as RenderDeployListItem[];

    const suspended = service.suspended ?? service.service?.suspended;
    const latestDeploy = deploys[0]?.deploy;

    return {
      configured: true,
      serviceStatus: suspended && suspended !== "not_suspended" ? `suspended (${suspended})` : "running",
      lastDeployStatus: latestDeploy?.status,
      lastDeployAt: latestDeploy?.finishedAt ?? latestDeploy?.createdAt,
    };
  } catch (err) {
    return { configured: true, error: err instanceof Error ? err.message : "Render API request failed" };
  }
}
