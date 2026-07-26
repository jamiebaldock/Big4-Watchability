// Persistence for the Alerts feature (close-swing push alerts + per-game
// bell subscriptions) - tables live in the same games.db as gameStore.ts
// (via rawDb) so they inherit the exact same durability story as game
// records: whatever disk games.db survives redeploys on, these survive too.
//
// Design notes mirroring gameStore's own conventions:
// - One row per device in alert_devices, keyed by a client-generated stable
//   UUID (persisted in the app's DataStore) rather than the FCM token -
//   tokens rotate (onNewToken), a device identity shouldn't.
// - alerts_sent is the fire-once guarantee: INSERT OR IGNORE keyed on
//   (device, game, type), checked-and-recorded atomically, so a poller
//   restart or overlapping tick can never double-send the same alert -
//   same WHERE-guard philosophy as gameStore's setPreview/setFinalRubric.
// - Favorites are SNAPSHOTS pushed by the client on register (favorites
//   live canonically in on-device DataStore; the server only needs a copy
//   to scope close-swing detection while the app is closed).
import { rawDb } from "./gameStore";

const db = rawDb();

db.exec(`
  CREATE TABLE IF NOT EXISTS alert_devices (
    device_id TEXT PRIMARY KEY,
    fcm_token TEXT,
    close_swing_enabled INTEGER NOT NULL DEFAULT 1,
    delivery TEXT NOT NULL DEFAULT 'both',
    favorites_only INTEGER NOT NULL DEFAULT 1,
    tier_threshold TEXT,
    leagues TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL,
    last_seen_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS alert_device_favorites (
    device_id TEXT NOT NULL,
    team_name TEXT NOT NULL,
    league_group TEXT,
    PRIMARY KEY (device_id, team_name)
  );

  CREATE TABLE IF NOT EXISTS alert_game_subs (
    device_id TEXT NOT NULL,
    event_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (device_id, event_id)
  );

  CREATE TABLE IF NOT EXISTS alerts_sent (
    device_id TEXT NOT NULL,
    event_id TEXT NOT NULL,
    alert_type TEXT NOT NULL,
    sent_at TEXT NOT NULL,
    PRIMARY KEY (device_id, event_id, alert_type)
  );
`);

// Additive migration (not a column in the original CREATE TABLE above) -
// James's already-live alert_devices/alerts_sent tables on Render's
// persistent disk predate this, same "ALTER TABLE, don't recreate" approach
// gameStore.ts's own ensureColumn uses for exactly this reason. NULL means
// "sent before this column existed" (unknown outcome), not "failed" - only
// ever written going forward by recordAlertOutcome below.
function ensureColumn(table: string, column: string, definition: string): void {
  const existing = db.prepare(`PRAGMA table_info(${table})`).all() as { name: string }[];
  if (!existing.some((c) => c.name === column)) {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
  }
}
ensureColumn("alerts_sent", "delivered", "INTEGER");

function now(): string {
  return new Date().toISOString();
}

export type AlertDelivery = "push" | "in_app" | "both";

// Matches gameStore's tier strings (games.tier). The threshold scopes which
// NON-favorite games a device gets close-swing alerts for; how the Phase 4
// detector maps an in-progress game against it is that phase's concern -
// storage just keeps the user's choice.
export type AlertTierThreshold = "solid" | "worth_your_time" | "instant_classic";

export interface AlertDevicePrefs {
  deviceId: string;
  fcmToken: string | null;
  closeSwingEnabled: boolean;
  delivery: AlertDelivery;
  favoritesOnly: boolean;
  tierThreshold: AlertTierThreshold | null;
  leagues: string[];
  favorites: Array<{ teamName: string; leagueGroup: string | null }>;
}

/**
 * Full-state upsert - the client always sends its complete current prefs +
 * favorites snapshot (it's a handful of rows), so registration, pref
 * changes, favorites changes, and FCM token rotation are all this one
 * idempotent call. Favorites are replaced wholesale in the same
 * transaction, never merged, so a team unfavorited on-device can't linger
 * server-side and keep firing alerts.
 */
export function upsertDevice(prefs: AlertDevicePrefs): void {
  const ts = now();
  db.transaction(() => {
    db.prepare(
      `INSERT INTO alert_devices
         (device_id, fcm_token, close_swing_enabled, delivery, favorites_only, tier_threshold, leagues, updated_at, last_seen_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(device_id) DO UPDATE SET
         fcm_token = excluded.fcm_token,
         close_swing_enabled = excluded.close_swing_enabled,
         delivery = excluded.delivery,
         favorites_only = excluded.favorites_only,
         tier_threshold = excluded.tier_threshold,
         leagues = excluded.leagues,
         updated_at = excluded.updated_at,
         last_seen_at = excluded.last_seen_at`
    ).run(
      prefs.deviceId,
      prefs.fcmToken,
      prefs.closeSwingEnabled ? 1 : 0,
      prefs.delivery,
      prefs.favoritesOnly ? 1 : 0,
      prefs.tierThreshold,
      prefs.leagues.join(","),
      ts,
      ts
    );
    db.prepare(`DELETE FROM alert_device_favorites WHERE device_id = ?`).run(prefs.deviceId);
    const insertFav = db.prepare(
      `INSERT OR IGNORE INTO alert_device_favorites (device_id, team_name, league_group) VALUES (?, ?, ?)`
    );
    for (const fav of prefs.favorites) insertFav.run(prefs.deviceId, fav.teamName, fav.leagueGroup);
  })();
}

/** The per-game bell. Subscribing to an already-belled game (or unsubscribing an unbelled one) is a harmless no-op, so the client can fire-and-forget toggles. */
export function setGameSub(deviceId: string, eventId: string, subscribed: boolean): void {
  if (subscribed) {
    db.prepare(
      `INSERT OR IGNORE INTO alert_game_subs (device_id, event_id, created_at) VALUES (?, ?, ?)`
    ).run(deviceId, eventId, now());
  } else {
    db.prepare(`DELETE FROM alert_game_subs WHERE device_id = ? AND event_id = ?`).run(deviceId, eventId);
  }
}

/**
 * Atomic check-and-record for the fire-once guarantee: returns true exactly
 * once per (device, game, type) - the INSERT OR IGNORE either claims the
 * slot (changes = 1, caller should send) or finds it already claimed
 * (changes = 0, someone already sent this alert; skip).
 */
export function claimAlertSend(deviceId: string, eventId: string, alertType: string): boolean {
  const result = db
    .prepare(`INSERT OR IGNORE INTO alerts_sent (device_id, event_id, alert_type, sent_at) VALUES (?, ?, ?, ?)`)
    .run(deviceId, eventId, alertType, now());
  return result.changes === 1;
}

/** Called once sendPush's actual result is known - separate from claimAlertSend above (which fires before the send, purely to prevent a double-send race) so the Admin page's delivery-rate stat reflects what FCM actually reported, not just "we attempted to send." */
export function recordAlertOutcome(deviceId: string, eventId: string, alertType: string, delivered: boolean): void {
  db.prepare(`UPDATE alerts_sent SET delivered = ? WHERE device_id = ? AND event_id = ? AND alert_type = ?`).run(
    delivered ? 1 : 0,
    deviceId,
    eventId,
    alertType
  );
}

export interface AlertDeliveryStats {
  registeredDevices: number;
  sentLastNDays: number;
  deliveredLastNDays: number;
  failedLastNDays: number;
}

/** The Admin page's push-delivery section - registered device count is a live snapshot; sent/delivered/failed are counted over the trailing [days] window from alerts_sent.sent_at. */
export function getAlertDeliveryStats(days: number): AlertDeliveryStats {
  const registeredDevices = (
    db.prepare(`SELECT COUNT(*) AS c FROM alert_devices WHERE fcm_token IS NOT NULL`).get() as { c: number }
  ).c;
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString();
  const row = db
    .prepare(
      `SELECT
         COUNT(*) AS sent,
         SUM(CASE WHEN delivered = 1 THEN 1 ELSE 0 END) AS delivered,
         SUM(CASE WHEN delivered = 0 THEN 1 ELSE 0 END) AS failed
       FROM alerts_sent WHERE sent_at >= ?`
    )
    .get(since) as { sent: number; delivered: number | null; failed: number | null };
  return {
    registeredDevices,
    sentLastNDays: row.sent,
    deliveredLastNDays: row.delivered ?? 0,
    failedLastNDays: row.failed ?? 0,
  };
}

export interface AlertDeviceRow {
  device_id: string;
  fcm_token: string | null;
  close_swing_enabled: number;
  delivery: string;
  favorites_only: number;
  tier_threshold: string | null;
  leagues: string;
}

/** Every device the Phase 4 poller should consider - close-swing on and a usable token. */
export function getAlertableDevices(): AlertDeviceRow[] {
  return db
    .prepare(`SELECT * FROM alert_devices WHERE close_swing_enabled = 1 AND fcm_token IS NOT NULL`)
    .all() as AlertDeviceRow[];
}

export function getDeviceFavorites(deviceId: string): Array<{ team_name: string; league_group: string | null }> {
  return db
    .prepare(`SELECT team_name, league_group FROM alert_device_favorites WHERE device_id = ?`)
    .all(deviceId) as Array<{ team_name: string; league_group: string | null }>;
}

/** The Admin page's "send test push" button - looks up a single device's own token to target it directly, rather than fanning out to every registered device. */
export function getDeviceFcmToken(deviceId: string): string | null {
  const row = db.prepare(`SELECT fcm_token FROM alert_devices WHERE device_id = ?`).get(deviceId) as
    | { fcm_token: string | null }
    | undefined;
  return row?.fcm_token ?? null;
}

export function getGameSubDeviceIds(eventId: string): string[] {
  const rows = db.prepare(`SELECT device_id FROM alert_game_subs WHERE event_id = ?`).all(eventId) as Array<{
    device_id: string;
  }>;
  return rows.map((r) => r.device_id);
}

/**
 * FCM rejected this token as dead (unregistered/invalid) - null it out so
 * the poller stops attempting sends, but keep the device row + prefs: the
 * same install re-registers with a fresh token on next app open and picks
 * up right where it left off.
 */
export function clearDeadToken(fcmToken: string): void {
  db.prepare(`UPDATE alert_devices SET fcm_token = NULL, updated_at = ? WHERE fcm_token = ?`).run(now(), fcmToken);
}
