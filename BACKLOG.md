# Feature & Bug Backlog

Logged from James's 2026-07-25 batch. Prioritization TBD.

## Bugs (Priority: Fix)

### P1: App load time hangs on empty-schedule leagues
**Status:** ✅ FIXED AND VERIFIED (commit fbd6786)  
**Description:** App took ~40 seconds to load when opening a league, especially one with no games scheduled today.  
**Root cause (confirmed via emulator + direct backend timing, not just code reading):** Once a league's full season window is known (every league spans 130-250+ days), `fetchScheduleChunked` splits it into ~21-day chunks and fetched each one **sequentially** — awaiting each chunk's full network round-trip before starting the next. A ~250-day season (NHL/NBA) needs ~12 chunks at ~2-3s each. Confirmed via direct curl timing (3 chunks: 11.2s sequential vs. 3.8s concurrent — no backend-side bottleneck) and via matched before/after app timing.  
**Not actually specific to "no games today"** — every league's full-season load pays this cost every time; NHL's current off-season just happens to be when James notices it most (MLB, currently in-season, has an equally long season window and would be equally slow).  
**Fix:** `fetchScheduleChunked` now fires every (league, chunk) request concurrently via `async`/`awaitAll` instead of a sequential loop.  
**Verified with matched before/after timing on the Android emulator** (same device, same NHL league switch, using the existing PERF FileLogger instrumentation):
- BEFORE: `fetchSchedule` 32.16s, total load 32.7s
- AFTER: `fetchSchedule` 6.14–6.65s, total load 6.9–8.0s
- **~4-5x faster.** Also confirmed the rendered result is correct (season day-tabs, empty state, Jump to next game button) — not just fast but still functioning.
**Note:** APK synced to phone folder, ready for James to confirm himself.

#### Follow-up (2026-07-27): pushing further below 7-8s
James asked to investigate further. Findings per option, all measured (not theorized):

1. **Server-side ESPN caching — did NOT exist, now added (commit 3776b46).** Confirmed by reading the full call chain: every scoreboard fetch hit ESPN fresh, every time, even for a date 9+ months in the past whose games are permanently final. Added a permanent file cache (reusing leagueCache.ts's primitives) for any date 2+ days in the past — "today"/future dates are never cached. **Verified locally: single 21-day chunk 8.83s cold → 0.006s warm (~1500x); full 12-chunk season 12.5s cold → 0.16s warm.** Needs a Render redeploy to take effect in production.
2. **Reducing chunk count — investigated, not worth it.** Tested 12 chunks fired truly concurrently via curl: 9.85s (worse per-chunk than smaller batches — the backend itself becomes the bottleneck under heavy concurrency, not the network). Total ESPN-call cost is the same whether split into many small requests or fewer large ones; caching (#1) solves the redundant-work problem far more effectively than chunk-size tuning would. Not implemented.
3. **Client-side same-session cache — implemented (commit a5b8294).** Server caching alone still needs one real HTTP request per chunk (fast once warm, but not free). Added an in-memory `Map` on `GameListViewModel` keyed by league, 60s TTL (to avoid showing arbitrarily-stale live scores on switch-back). **Verified on emulator: switching away and back to NHL within the TTL window made zero network calls, confirmed via log (no fetch lines at all) and correct instant rendering.**
4. **Prefetching likely-next leagues — investigated, not implemented.** Given #1 and #3 already deliver massive wins with low complexity/risk, prefetching's added complexity (background work, battery/bandwidth cost for leagues never visited) isn't worth it right now. Worth reconsidering only if #1+#3 together still leave cold-load time feeling slow.
5. Nothing else found worth pursuing at this pass.

**Combined effect (not yet measured together against production since #1 needs a Render redeploy first):** first-ever cold load stays ~7-8s (parallelization fix, already live); any repeat load of a previously-warmed date range (by anyone) should be dramatically faster once #1 is deployed; same-session league switch-backs are already instant via #3, live now.

#### Second follow-up (2026-07-27): pushing cold-start further + loading screen
James asked to push speed further still (this time specifically the genuinely-first-ever-fetch case, since caching only helps repeats) and wanted the plain spinner replaced (backlog #F3). Findings:

1. **Persistent cross-restart client cache — investigated, not implemented this pass.** Would need a new on-disk repository (file or Room), cache-invalidation design, and stale-while-revalidate UI handling - real complexity for a narrower win than #2 below (only helps a previously-viewed league within some staleness window, not a genuinely new one). Deprioritized in favor of #2, which helps every cold load unconditionally.
2. **Narrow-window-first progressive loading — implemented (commit ff753e1).** `load()` now fetches a small window around today (or the season start, if today's outside the season) first and paints it immediately, then streams in the full season behind it. A monotonic token guards against a stale second-phase fetch overwriting a newer league switch. **Verified on emulator, true cold start (fresh install, nothing cached anywhere): first paint 3166ms, full season 5687ms** - down from the ~7-8s "nothing renders until everything arrives" baseline. This is what options 2 and 3 from James's list amounted to in practice - implemented together as one mechanism rather than two.
3. Also fixed a bug found along the way: `FileLogger.log()` wrote to disk before logcat, so a failed disk write (scoped storage blocking legacy `WRITE_EXTERNAL_STORAGE` on this Android version, confirmed even after explicitly granting the permission) silently ate the logcat line too - every PERF measurement this whole investigation had to work around by hand-deriving durations from raw timestamps. Now logcat fires first, unconditionally.
4. Nothing else found worth pursuing.

**Loading screen (backlog #F3) — done (commit 8ca649b).** Replaced the plain `CircularProgressIndicator` with three teal dots bouncing in a staggered wave plus a rotating one-line status message ("Finding the good games...", etc.), matching the app's existing playful voice. One shared composable (`LoadingIndicator`) covers both the app-launch wait and the Games-tab per-league wait - same call site both used before.

**Net effect:** cold app launch to a usable screen is now ~3.2s (was ~7-8s after the first P1 fix, ~40s before any of this work started), with the loading animation making even that wait read as intentional rather than a stall.

### P2: Long-press "add team as favorite" doesn't sync to Favorites > Past Games
**Status:** ✅ FIXED (commit 65d9a07)  
**Description:** When long-pressing a game tile to quick-add a team as favorite, that team's past games didn't automatically appear in Favorites > Past Games until page refresh.  
**Root cause:** FavoritesTab's LaunchedEffect only reacted to `favoriteTeams` changes, missing the edge case where user adds favorite on another tab, then navigates to Favorites.  
**Fix:** Dual LaunchedEffect strategy: one runs on tab entry (Unit dependency), another on favoriteTeams change. Ensures immediate refresh when navigating to Favorites tab after adding a favorite from any screen.

### P3: Diamondbacks still missing YouTube highlights
**Status:** ✅ FIXED FOR REAL (commit 6982e97) — supersedes 928116f, which was backwards and never worked  
**Description:** Diamondbacks games not getting YouTube highlights.  
**What went wrong the first time:** Commit 928116f was based on an unverified assumption (an admin-page comment claiming "ESPN uses D-BACKS abbreviation") and mapped D-BACKS → Diamondbacks. But live ESPN data confirms `displayName` is already the full "Arizona Diamondbacks" — that mapping's trigger condition never occurs, so the fix never actually changed behavior. James caught this because the bug was still live in production.  
**Real root cause (verified against live @MLB channel data):** it's the *opposite* direction — ESPN's name is the full "Diamondbacks", but the official YouTube channel's real titles abbreviate to "D-BACKS" ("D-BACKS vs. NATIONALS: Official Full Game Highlights..."). The search query/match was built from "Diamondbacks", which never appears in a real title.  
**Fix:** Replaced the single hardcoded branch with a general `TEAM_NICKNAME_ALIASES` table in youtubeClient.ts (per James's ask — not a one-team patch). Verified the corrected direction against real captured title text via logic simulation (confirmed match; old logic confirmed no-match).  
**Audit of other leagues/teams** for the same "official channel abbreviates differently than ESPN's name" pattern, checked against live channel data: NBA's 76ers, MLB's Red Sox/White Sox/Blue Jays/Guardians, NFL's Buccaneers — all confirmed clean, no alias needed. Red Sox/White Sox both reduce to just "Sox" under the existing last-word extraction (a real but minor quirk — real titles still contain "SOX" as a substring so matching still succeeds, just a weaker query) — left as-is since it isn't actually broken.  
**Note:** Backend-only fix, no APK rebuild needed; takes effect on next highlights search/poll.

### P4: Add screen doesn't filter by currently-selected league on Favorites tab
**Status:** ✅ FIXED (commit 2417fce)  
**Description:** Tapping "add teams" or "add players" from Favorites tab always defaults the add screen to NBA, regardless of which league is currently selected on the Favorites tab. Should default to the current selection.  
**Fix:** Thread selectedLeague through AppRoot callbacks to FavoriteTeamsScreen and FavoritePlayersScreen. Both now accept defaultLeague param (defaults to NBA for backward compat) instead of hardcoding.

---

## Features (Priority: Design/Scope)

### F2: Player social media feeds (X/Twitter integration)
**Status:** Design/research needed  
**Description:** Show favorite players' and teams' X/Twitter feeds somewhere in the app. Possibly scoped to just favorite players initially; could be a dropdown/icon on the Favorites tab or integrated into a player detail view.  
**Scope:** Large — X API integration, feed management, UI design, handling auth/rate limits  
**Notes:** Research Twitter API restrictions and cost

### F3: Proper splash/opening screen instead of loading spinner
**Status:** ✅ DONE (commit 8ca649b) — see P1's "second follow-up" section below for details  
**Description:** Replace blank-screen-with-spinner loading state with a short intentional animation so it doesn't read as a stall.  
**Fix:** Three teal dots bouncing in a staggered wave + rotating one-line status message, replacing the plain spinner in the one shared `LoadingScreen()` composable both the app-launch wait and Games-tab per-league wait already used.

### F4: Push notification deep-linking to specific game tiles
**Status:** ✅ BUILT AND CONFIRMED WORKING (commits d143b11, f7d2cb1) — phone-tested by James 2026-07-27  
**Description:** When user taps a push notification, deep-links to the specific day/league of the game referenced instead of just opening the app generically.  
**Finding:** Was NOT actually blocked — Alerts phases 1-5 were already fully live, and the backend already included `eventId` in every push payload. The gap was entirely on the mobile tap-handling side (a bare launch intent with no extras).  
**Fix:** Backend now also sends `lg`/`utc` in the push payload. New `DeepLinkViewModel` parses a tapped notification's intent extras; `AppRoot` force-closes any open overlay, switches to Games on the target league, and jumps to the target date via the existing `jumpToDate()` (same mechanism the calendar picker uses). `MainActivity` handles both cold start and warm start (`onNewIntent` + `singleTop` launchMode).  
**Scope note:** Lands on the correct day-tab with the game's tile visible — does not open the game-detail popup directly or auto-scroll/highlight the specific tile (would've needed a new per-sport single-game backend endpoint; out of scope for this pass).  
**APK:** synced to phone, ready for James to test via a real close-swing alert or (once available) a manual test push.

### F5: Admin area expansion — stats + push notifications
**Status:** ✅ COMPLETE  
**Description:** Admin access to a stats dashboard and the ability to send push notifications from that admin area.  
**Fix:** Render/Anthropic/push-delivery stats added to the Admin dashboard (`26706c8`); "Send test push" button added for deep-link testing (`1ad72bb`) — on top of the existing highlights-stats admin page (`4b03b8a`).

### F6: History tab season selection for "All leagues" mode
**Status:** ✅ CLOSED — James confirmed 2026-07-27 current behavior is fine as-is, no change needed  
**Description:** Currently, per-league season chips ("2025-26", etc.) don't make sense when "All leagues" is selected. Only "This season" and "All time" work across leagues.  
**Resolution:** No design change wanted — existing "This season"/"All time"-only behavior for "All leagues" mode stays as-is.

### F7: Full historical/"All time" backfill for every league
**Status:** ✅ COMPLETE (2026-08-03)  
**Description:** James's goal: every league's History "All time" tab should be backed by real past seasons, without keeping more data live in production than the app actually surfaces.  
**Closing note:** NFL got its full 90+ Barn Burner sweep (`e2422b1`, 70 games across 2001-2023; gap in 2010/2011 later found and filled, `be14c09`). NHL got its own sweep (`3d1cfa6`, 128 games across 2001-02 through 2023-24). WNBA already had `historicalWatchabilityWnba.json` (576 games) from earlier work. Separately, `ddb58ef` replaced the whole "All time" mechanism: instead of a per-league calibrated score floor, it's now a flat **top-20-per-league cap by effective score rank**. That change obsoletes the "calibrate NFL/NHL/WNBA's own All-time threshold" step below entirely — there's no threshold left to calibrate for any league, NBA/MLB's included. AboutScreen's History copy was already updated to describe the rank-based cap generally (`068f5b6`, `0adb167`), not per-league score numbers.
**⚠️ Standard process going forward (James's explicit call, 2026-07-31) - read before starting NFL/NHL:**
1. Collect and score full older seasons **locally only** (`backfillRawStats<League>Historical.ts` per league) - real per-season files, gitignored (`backend/.gitignore`'s `data/*RawStats_*.json`), never committed. Regenerable anytime by rerunning the script.
2. Extract just the games that clear that league's own real-data-calibrated All-time bar into a small curated file (`extract<League>BarnBurners.ts` → `<league>HistoricalBarnBurners.json`) - **this** is what gets committed and migrated into gameStore, not the full raw pull.
3. Named-season chips for the older seasons stay excluded (`getSeasonLabels`'s year-cutoff pattern) - only the curated games surface, only under All-time.

This is NBA's original `BARN_BURNER_EVENT_IDS` approach exactly - collect wide locally, keep only what clears the bar. **MLB got this backwards first** (see its own entry below) and paid for it with a real production outage - don't repeat that for NFL/NHL.
**Per-league status (final):**
- **NBA** — full backfill for 2024-25/2025-26, plus a margin-filtered 90+-only "Barn Burner" sweep across all 21 older seasons back to 2002-03 via `investigateNbaBarnBurners.ts`/`finalizeBarnBurners.ts`. Only 4 games cleared 90+ across those 21 seasons.
- **MLB** — full backfill, 9 pre-2025 qualifying games curated in after a first-pass mistake (see note below).
- **NFL** — full 90+ Barn Burner sweep, 70 games across 2001-2023 (`e2422b1`; a 2010/2011 gap later found and filled, `be14c09`).
- **NHL** — full sweep, 128 games across 2001-02 through 2023-24 (`3d1cfa6`).
- **WNBA** — `historicalWatchabilityWnba.json` (576 games) feeds its own top-20 pool same as the others.

**Worth remembering — MLB's first-pass mistake:** its first attempt (2026-07-30) fully migrated all 21 older seasons (~50k games) straight into gameStore, shipped, and immediately caused a real production outage (Render 502s) the next day — the migration re-ran on every server boot instead of once, and `db.prepare()` was called ~100k+ times in one tight synchronous loop, exhausting Node's heap. Both fixed (`migration_flags`/`runOnceEver`, a module-level `statements` cache). Pruned back down to just the games that actually qualify. NFL/NHL's later sweeps followed the corrected collect-locally/curate-then-migrate process from the start and didn't repeat this.

**Superseded:** the per-league "All time" score-threshold calibration (NBA 90, WNBA 75, MLB 90, NFL/NHL TBD) and the planned AboutScreen follow-up to name each league's cutoff are both moot — `ddb58ef` replaced score thresholds entirely with a flat top-20-per-league rank cap, so there's no per-league number left to document or calibrate.

---

## Monetization (Design/Scope)

**⚠️ Pivot, 2026-08-27 (James's call): M1–M3 below (the Pro-unlock/feature-gate plan) are superseded by M4 — ads-with-remove-ads-IAP.** Kept for history; read M4 first for the current plan.

### M1: Launch timing for Pro monetization — SUPERSEDED by M4
**Status:** Recommendation only — pricing not yet settled, nothing implemented
**Description:** Considering a one-time "Pro" unlock: NBA stays free with full features; MLB/NFL/NHL free tier limited to Games tab only (no Standings/Stats/News/History/customization); Pro purchase unlocks full MLB/NFL/NHL access + rubric weight customization across all 4 leagues + advanced alert types (starting-soon, close-swing). WNBA excluded from monetization costing entirely (short season, low historical viewership).
**Season overlap (reference year 2026):** NBA/NHL ~Oct–June, NFL ~Sept–Feb, MLB ~Apr–Oct/Nov. The only window all 4 leagues are simultaneously highly active is **early-to-mid October** (NBA/NHL season openers land while NFL is in full regular season and MLB is in its postseason/World Series).
**Recommendation:** Soft-launch (or continue running) with monetization off during the lower-stakes Aug–Sept 2026 stretch (MLB mid/late-season + NFL preseason/early season) to gather crash reports and reviews at low stakes. Flip the Pro paywall live in **early-to-mid October 2026**, timed with NBA/NHL opening night — a first-time user's very first session can then show all 4 leagues live at once, which is also the strongest possible demo of the "unlock 3 more leagues" value prop and coincides with peak US sports attention overall.
**Notes:** Codebase feasibility researched 2026-07-27 (Explore agent pass) — no Google Play Billing Library integration exists yet, would be built from scratch. Natural gate seams identified: `AppRoot.kt`'s existing `isSupported`/`ComingSoonTab` dispatcher (league/tab visibility), `RubricWeightsScreen.kt` (customization gate, single file), `AlertsSettingsScreen`/`AlertsViewModel` (alert-type gate). Client-side `isPro` flag (DataStore, same pattern as existing settings) is cheap; server-side purchase enforcement would be new work since `devServer.ts` currently has no per-device/per-user authorization on any data endpoint.

**Decisions locked in 2026-07-27 (James, via pop-up questions):**
- Pricing model: **one-time Pro unlock** (no subscription)
- Price: **$4.99**
- Enforcement: **server-verified purchases** (Google Play Developer API token verification + backend route guards on MLB/NFL/NHL Standings/Stats/News/History — not just a client-side flag)
- Ad budget: **small paid budget (~$100–500)** at launch, targeted burst rather than sustained spend

### M2: Full task list + timeline — SUPERSEDED by preseason-trial strategy (see M3)
**Status:** Superseded 2026-07-27 — original plan assumed a single Oct 13–21 launch date; James proposed launching earlier instead (see M3). Kept here for history only.
~~Original Phase 7 target was "LAUNCH ~Oct 13–21, flip Pro paywall live day-of."~~ Replaced by the preseason-trial-window strategy below.

### M3: Preseason trial-window launch strategy — SUPERSEDED by M4 (see below)
**Status:** Superseded 2026-08-27 — James pivoted away from the whole Pro-unlock/feature-gate model to ads + a "Remove Ads" IAP instead (M4). Kept here for history only; nothing in this section was ever built. Full task list + timeline for the (now-superseded) plan was delivered as a formatted PDF — see [Big4_Pro_Launch_Playbook.pdf] (sent to James 2026-07-27), unique task names below match the PDF exactly so either of us can reference a task by name.
**The pivot:** instead of launching and flipping the Pro paywall live on the same day, launch publicly during NBA preseason (~Oct 1–5, NBA's 2026-27 preseason reportedly starts Oct 5 per fan/sports-media sites, not yet NBA's own official release) while MLB's postseason and NFL's regular season are already active. Everyone gets **every Pro feature free** as a time-boxed trial from launch through NBA/NHL opening night (**Oct 20**, per James — historically the 2nd-last Tuesday of October), then the gate closes automatically on **Oct 21**, right as interest peaks and people who got hooked during the trial are prompted to buy.
**Resolved 2026-08-27:** Play Console account ("Tech3D") confirmed **Personal account type**, created 2026 (well after the Nov 13, 2023 cutoff) → mandatory **12-tester/14-consecutive-day closed test applies**, no exemption available. This constraint carries forward to M4 below regardless of monetization model.

**Phase A — Foundations (Jul 28 – Aug 10):** Tip-Off Setup (Play Console account), Merchant Bench (Payments profile — James only, banking info), Roster Check (confirm account type), Playbook Draft (backend entitlement schema), Billing Client Wiring (add Play Billing Library — none exists yet).

**Phase B — Core Build (Aug 11 – Aug 31):** Entitlement Vault (backend purchase verification + route guards on MLB/NFL/NHL endpoints), Buy Button Flow (client purchase flow + Restore Purchase), Gate Keeper Rollout (feature gating in `AppRoot.kt`/`RubricWeightsScreen.kt`/`AlertsSettingsScreen`), **Trial Switch** (new: server-side date check that treats everyone as Pro until the Oct 20 cutoff, reusing the Gate Keeper seams), Storefront Polish (listing/screenshots/icon), Product Shelf ($4.99 IAP product + tax/compliance).

**Phase C — QA & First Upload (Sep 1 – Sep 7):** Sandbox Scrimmage (license-tester purchase testing), Cheater Check (adversarial faked-isPro test), Free Tier Regression, First Upload (first signed AAB to a test track).

**Phase D — Beta Squad / Closed Testing (Sep 8 – Sep 21):** **Beta Squad Recruitment** (12–15 real opt-in testers — start ASAP, biggest schedule risk in the whole plan), 14-Day Clock (mandatory consecutive days from last qualifying opt-in), Feedback Huddle.

**Phase E — Production Green Light (Sep 22 – Sep 30):** Production Green Light (apply for production access), Ad Creative Kit, **Countdown Banner** (in-app "Pro preview ends Oct 20" banner + reminder push), Final Smoke Test.

**Phase F — Preseason Tip-Off Launch (Oct 1 – Oct 5):** Preseason Tip-Off Launch (public release goes live, trial active for everyone), Ad Burst (spend the $100–500 here, launch-week acquisition only), Community Drop (organic posts: r/nba, r/nfl, r/mlb, r/hockey + team subreddits).

**Phase G — Trial Window (Oct 1 – Oct 20):** Countdown Banner stays live; Opening Night Watch (monitor usage, reconfirm official preseason dates once NBA publishes them).

**Phase H — Opening Night Cutoff (Oct 20–21):** Last Chance Nudge (free in-app/push reminder Oct 19–20, retention not acquisition — no ad spend), Opening Night Cutoff (trial flag expires automatically; verify morning-of that it actually re-gated).

**Phase I — Post-Launch Watch (Oct 21+):** monitor purchase conversion, reviews, crash rate; decide on any follow-up promo.

**Advertising plan (small budget, ~$100–500):**
- Sports is a high-CPI category — treat the budget as a tightly-targeted **launch-week acquisition burst** (Phase F's Ad Burst), not sustained spend.
- Organic/ASO first (free, drives most installs): store listing keywords/screenshots/preview video, plus organic posts (not ads) in r/nba, r/nfl, r/mlb, r/hockey, team subreddits — Community Drop.
- The Oct 20 cutoff reminder (Last Chance Nudge) is a **free retention push to existing installs**, not a paid acquisition moment — paid spend stays concentrated at launch.
- Skip Apple Search Ads — Android-only app, no iOS project exists in this repo.
- The closed-testing Beta Squad doubles as day-one reviewers/word-of-mouth seed.

**Info still needed from James:** Roster Check result (account type); Merchant Bench banking details (must be entered by James — cannot be done on his behalf); Beta Squad Recruitment names (12–15 real people); ad platform account/payment setup (Google Ads / Meta Ads Manager); confirmation of NBA preseason/opening-night dates once officially published; sign-off that the trial-end messaging tone (playful, Player Hater Mode-style) is right.

### M4: Ads + "Remove Ads" IAP (current plan, replaces M1–M3)
**Status:** Banner ad wired and building on Android with Google's official TEST ad unit (2026-08-27) — everyone sees the same sample ad right now, nothing is a real monetized impression yet. "Remove Ads" purchase not started.
**The pivot:** every league/feature stays fully free for everyone — no gating logic anywhere, no trial-window cutoff, no per-league entitlement enforcement. Revenue instead comes from an AdMob banner shown to all users, plus a single one-time "Remove Ads" IAP that flips a local flag to hide it. This drops nearly all of M1–M3's complexity: no backend entitlement schema, no server-verified route guards on MLB/NFL/NHL endpoints, no `AppRoot.kt`/`RubricWeightsScreen.kt`/`AlertsSettingsScreen` feature gates, no Trial Switch/Countdown Banner/Opening Night Cutoff machinery.
**Why lower verification stakes than M1–M3:** the worst case of someone spoofing the "ads removed" flag is lost ad revenue from that one user, not exposed paid data — so a client-side DataStore flag (same pattern as the app's other settings) is acceptable rather than needing Google Play Developer API server-verification like the old plan required for feature access.

**Built (2026-08-27):**
- `mobile/app/build.gradle.kts` — added `com.google.android.gms:play-services-ads:23.5.0`
- `mobile/app/src/main/AndroidManifest.xml` — added the required AdMob `APPLICATION_ID` meta-data, using Google's published **test** App ID (`ca-app-pub-3940256099942544~3347511713`)
- `mobile/app/src/main/java/com/nbawatchability/app/ui/AdBanner.kt` — new; wraps the View-based `AdView` in `AndroidView` (AdMob has no first-party Compose primitive yet), using Google's published **test** banner ad unit ID (`ca-app-pub-3940256099942544/6300978111`), initializes `MobileAds` on first composition
- `mobile/app/src/main/java/com/nbawatchability/app/ui/AppRoot.kt` — `AdBanner()` placed inside the Scaffold's `bottomBar` slot, stacked above `ScrollableBottomNavBar` (the tab row), so it shows on every tab consistently, positioned above rather than below the nav row
- Debug APK rebuilt and synced to `Big4Watchability Phone App/Big4Watchability-app-debug.apk` for on-device test

**Still open:**
0. ✅ `play-store/privacy-policy.txt` and `play-store/store-listing.txt` updated 2026-08-27 for accuracy (added AdMob + Firebase Cloud Messaging disclosure, dropped the now-false "No ads/No tracking" claims). Hosting also done the same day: `backend/src/privacyPolicyPage.ts` (new) is served at `GET /privacy-policy` by `devServer.ts`, verified 200 OK locally — will be live at **https://nba-watchability.onrender.com/privacy-policy** once this commit is pushed and Render redeploys (not yet pushed as of this entry). Kept as a hand-synced HTML copy of the .txt source since the backend deploy doesn't include files outside `backend/` — update both together when the policy changes.
1. Swap the test App ID/ad unit ID for real ones once James registers the app in an AdMob account (needs its own Google account setup, separate from Play Console).
2. GDPR consent: Google's User Messaging Platform (UMP) SDK needs wiring before EU users can be served personalized ads — not yet added.
3. Decide on ad placement beyond the one banner (interstitials? none at all?) and whether banner-only is the final call.
4. Build the "Remove Ads" IAP: single non-consumable Play Billing product, purchase flow, Restore Purchase, and the DataStore flag that suppresses `AdBanner` once set.
5. Play Console Data Safety section needs updating to disclose ad usage; content rating may need revisiting.
6. Closed-testing requirement (12-tester/14-day) confirmed to apply (2026-08-27: account is Personal type) — unaffected by this pivot, it's a publishing rule not a monetization-model consequence. **Beta Squad Recruitment (12–15 real opt-in testers) is now the biggest schedule risk in the whole plan** — worth starting as soon as an app listing exists, since the 14-day clock only starts once testers actually opt in.

---

## Removed

- **F2 (Player X/Twitter feeds)** — Removed 2026-07-25. Research confirmed: no free legal alternative, official X API costs $75–$150/month for typical usage. Not worth the cost/benefit for a feature-polish item.
- **F1 (Multiple news sources picker)** — Removed 2026-08-03. James: not an option right now.

---

## Quick Wins (Trivial/1-liners, could do now)

*(Removed 2026-07-27 — this section only listed P2/P3/P4, which are all already fixed above. Nothing currently queued here.)*
