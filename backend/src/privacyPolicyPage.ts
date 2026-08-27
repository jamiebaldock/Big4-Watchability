// Served at GET /privacy-policy (devServer.ts) so Play Console has a real,
// public URL to link to for the store listing's required privacy policy
// field - play-store/privacy-policy.txt (repo root) is the source-of-truth
// plain-text draft; this HTML is a manually-kept-in-sync copy of the same
// content, since the backend deploy doesn't include files outside backend/.
// Update both together when the policy changes.
export const PRIVACY_POLICY_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Privacy Policy - Big4 Watchability</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; max-width: 720px; margin: 0 auto; padding: 32px 20px 64px; color: #1a1a1a; line-height: 1.55; }
  h1 { font-size: 1.5rem; margin-bottom: 4px; }
  .updated { color: #666; font-size: 0.9rem; margin-bottom: 32px; }
  h2 { font-size: 1.1rem; margin-top: 32px; margin-bottom: 8px; }
  ul { padding-left: 20px; }
  a { color: #1a56db; }
</style>
</head>
<body>
<h1>Privacy Policy for Big4 Watchability</h1>
<p class="updated">Last updated: August 27, 2026</p>

<p>Big4 Watchability ("the app") does not require an account and does not collect your name, email address, or other identifying information. It does show ads and use push notifications, both described below.</p>

<h2>What the app does not do</h2>
<ul>
  <li>No account creation, sign-in, or sign-up of any kind.</li>
  <li>No collection of your name, email address, contacts, or photos.</li>
  <li>No data is sold to third parties.</li>
</ul>

<h2>Advertising</h2>
<p>The app shows banner ads via Google AdMob to support development. AdMob may collect device identifiers (such as your advertising ID) and general usage data to serve and measure ads, and may use this data across other apps you use, per Google's own advertising policies. A one-time in-app purchase ("Remove Ads") is available to disable ads entirely. See Google's policy at <a href="https://policies.google.com/technologies/ads">policies.google.com/technologies/ads</a> for how AdMob handles this data.</p>

<h2>Push notifications</h2>
<p>If you enable Alerts (starting-soon or close-game notifications) in Settings, the app registers your device with Firebase Cloud Messaging (a Google service) so it can be sent a notification. This registration uses a device token, not your name or email. You can disable Alerts at any time in Settings, which stops new notifications; see Google's policy at <a href="https://firebase.google.com/support/privacy">firebase.google.com/support/privacy</a> for how Firebase handles this data.</p>

<h2>What's stored on your device</h2>
<p>The app saves a small set of preferences locally on your device only, using Android's standard app-preferences storage: your chosen watchability-rating weights, which leagues and teams/players you've favorited, your starred games, and which league you last viewed.</p>
<p>None of this ever leaves your device except as described above (ads, push notifications). Uninstalling the app deletes it.</p>

<h2>Network requests</h2>
<p>To show you game schedules, scores, and previews, the app makes standard internet requests to:</p>
<ul>
  <li>The app's own backend server, to fetch game data and pre-written game previews across its supported leagues.</li>
  <li>ESPN's public content servers, to load team logo images.</li>
  <li>YouTube, to search for and play official highlight videos.</li>
</ul>
<p>As with any internet request, your device's IP address is inherently visible to these servers as part of normal network communication - the same as visiting any website. The app's own backend does not log, store, or associate requests with any personal profile.</p>

<h2>Children's privacy</h2>
<p>The app does not knowingly collect personal information from children. Ad personalization for users known to be under 13 is restricted per Google Play's Families policy where applicable.</p>

<h2>Changes to this policy</h2>
<p>If this policy ever changes, the update will be posted here with a revised "Last updated" date.</p>

<h2>Contact</h2>
<p>Questions about this policy can be sent to: <a href="mailto:help@tech3d.com.au">help@tech3d.com.au</a></p>
</body>
</html>
`;
