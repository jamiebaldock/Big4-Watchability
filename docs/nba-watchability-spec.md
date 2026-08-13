# NBA Watchability App — Build Spec

## 1. What this app does

A mobile app (Android first, iOS later) that lists NBA games over a date range and shows how "watchable" each one is — **without ever revealing scores or winners** — so a user can decide what to watch without being spoiled. It also tracks games live, showing progress and, from the end of the 3rd quarter onward, a live watchability score so the user can jump into a good game already in progress.

---

## 2. Feature list (source of truth — build against this)

**Core scoring**
1. 100-point "Watchability Score" rubric computed per game:
   - Final margin — 25 pts (1–3: 25 | 4–6: 20 | 7–10: 13 | 11–15: 7 | 16–20: 3 | 20+: 0)
   - Clutch drama — 20 pts (within 5 in last 2 min: +8, lead change/tie in final minute: +6, decided on final possession: +6)
   - Buzzer-beater bonus — +10 pts (game-winner in final 3 seconds; can push score over 100)
   - Comeback factor — 15 pts (winner's largest deficit: 20+: 15 | 15–19: 10 | 10–14: 6 | <10: 0)
   - Lead changes/ties — 10 pts (1 pt per 2, capped at 10)
   - Overtime — 10 pts (+7 for OT, +3 more for 2OT+)
   - Star/statistical performance — 10 pts (50pt/historic: 10 | 40+/triple-double: 6 | 35+/near triple-double: 3)
   - Stakes — 10 pts (playoff/rivalry/seeding implications; pre-game only, spoiler-safe)
2. Score maps to a tier: 🔥 Instant Classic (85+) · ⭐ Worth Your Time (65–84) · 👍 Solid (45–64) · 😴 Skippable (<45)
3. Live games get a "score so far" from the rubric criteria resolved up to the current point — **but this is only computed/shown from the end of Q3 onward.** During Q1–Q2, no score or tier is shown at all, only progress (period + clock).

**Spoiler protection**
4. Default view shows tier badge only, never the raw number (numeric toggle available, off by default).
5. Games list in schedule order by default (not sorted by score); optional "best first" sort toggle.
6. Each game has a one-line spoiler-free "hook" — sells the matchup/drama without revealing winner, score, or ending.
7. Hook text is blurred until the user taps it.
8. A separate "full breakdown" reveal shows *how* the game played out (comeback size, OT, buzzer-beater flag, etc.) — still never who won or the score.
9. Upcoming-game hooks are based only on pre-game context (matchup, stakes, storylines) — nothing result-based.

**Data & date range**
10. User selects a date range via quick-select chips (Yesterday / Last 3 days / Last week) or custom start/end dates.
11. Range extends into today and the upcoming week, not just the past.
12. Game data comes from a structured, free sports data API (e.g. balldontlie, ESPN's public endpoints, or similar) — not web search or an LLM.
13. Rubric math runs natively on-device (Kotlin for Android, Swift for iOS) — no AI call needed for scoring.
14. An LLM is used server-side only for two fuzzy, non-numeric bits: the spoiler-free hook sentence, and the 0–10 stakes judgment.
15. Backend fetches/scouts each day once and caches the result; all users share that single fetch/LLM call.

**Live game handling**
16. Upcoming games show scheduled tip-off time converted to the user's local timezone.
17. In-progress games show a "LIVE" indicator plus current period (Q1–Q4, OT1, OT2, etc.) and clock, so users can see how far a game has progressed.
18. Live games show a live-updating watchability score/tier **starting at the end of Q3** (per point 3), refreshing periodically so users can jump in mid-game.

**Architecture**
19. Small backend service (cloud function) holds all API keys, calls the sports data API, computes/caches the LLM-derived hook + stakes fields once per day, and serves clean JSON to the app. Also polls more frequently during live windows to update period/clock/live-score.
20. Client app is a thin consumer of that cached JSON — no keys embedded in the APK/IPA.
21. Same JSON schema and scoring logic ports 1:1 across Android and iOS — the rubric is implemented once (as pseudocode/spec below) and translated into each platform's native language, not re-derived.

---

## 3. Visual design direction

- **Style:** Dark, bold sports-broadcast look (genre-level reference: ESPN/Athletic/Bleacher-Report-style dark UI conventions — no ESPN branding, logos, colors, or copied layouts of any kind).
- **Palette:** Dark navy/charcoal base (`#101418`–`#1A2027` range), high-contrast off-white text, saturated accent colors reserved for status: red/orange for LIVE, gold/orange for 🔥 tier, blue for 👍, muted gray for 😴 — consistent with the existing prototype artifact's tier colors.
- **Typography:** Bold, condensed weight for team matchups and scores; a clear visual hierarchy so team names > tier badge > hook text > metadata.
- **Layout:** Day-by-day tabs or horizontal swipe between days (not one long infinite feed, not a calendar drill-down). Each day's tab shows its own list of game cards in schedule order.
- **Badge prominence:** Medium — visible as a clear pill/tag per card (icon + label, e.g. "🔥 INSTANT CLASSIC"), not oversized/dominant, not shrunk to icon-only. Matches the existing web prototype's `.wl-tier` treatment.
- **Reference prototype:** The existing React artifact (`nba-watchability.jsx`) is the canonical visual/UX reference for card layout, blur-to-reveal hook interaction, and tier styling — mobile should feel like a native port of that, not a redesign.

---

## 4. Architecture overview

```
┌─────────────────┐      ┌──────────────────────┐      ┌───────────────────┐
│  Sports data API │ ───▶ │   Backend (cloud fn)  │ ───▶ │  Android / iOS app │
│ (balldontlie /   │      │  - fetch + cache daily│      │  - reads JSON only │
│  ESPN endpoints) │      │  - rubric scoring      │      │  - renders UI      │
└─────────────────┘      │  - LLM: hook + stakes  │      │  - no API keys     │
                          │  - live poll loop      │      └───────────────────┘
                          └──────────────────────┘
                                    │
                          ┌──────────────────────┐
                          │  Cache/DB (JSON store)│
                          └──────────────────────┘
```

- **Backend hosting:** free-tier cloud function (Google Cloud Functions or AWS Lambda), auto-generated URL (no custom domain for v1, per decision).
- **Cache/DB:** free-tier managed Postgres (e.g. Supabase/Neon) or simple JSON blob storage — whichever is simpler to wire up with the chosen cloud function provider.
- **Scheduler:** cron trigger once daily for the full-day scout; a separate frequent poll (every 1–2 min) active only during detected live-game windows to update period/clock/live-score.
- **Secrets:** sports-data API key and Anthropic API key stored in the cloud provider's secrets manager — never in client code or committed to git.
- **Repo:** single GitHub repo, monorepo-style: `/backend` (cloud function code) and `/mobile` (Android app first, `/mobile-ios` added later).
- **CI/CD:** GitHub Actions — lint/build on push; optional auto-deploy of backend function on merge to main.
- **Rate/cost caps:** backend enforces a max daily LLM call budget (one scout pass/day + live-window updates only, no per-user-triggered LLM calls) and basic request throttling on the public endpoint.

---

## 5. Data contract (backend → app JSON)

Extend the existing per-game schema (already used in the JSX prototype) with status/timing fields:

```json
{
  "a": "away team name",
  "h": "home team name",
  "stt": "final | live | upcoming",
  "utc": "2026-06-12T00:30:00Z",
  "q": 3,
  "clk": "7:42",
  "m": 6,
  "cb": 18,
  "lc": 14,
  "ot": 0,
  "c5": true,
  "lcf": true,
  "fp": true,
  "bz": false,
  "st": "great",
  "sk": 8,
  "hook": "spoiler-free one-liner",
  "score": 78,
  "score_visible": true
}
```

Notes:
- `score` and `score_visible` are computed backend-side (or client-side from the same rules) — `score_visible` is `false` for any live game still in Q1 or Q2, and `true` for final games and live games from end-of-Q3 onward.
- `utc` is always in UTC; the client converts to local time for display (point 16).
- All scoring fields (`m`, `cb`, `lc`, etc.) reflect "so far" values for live games, final values for completed ones.

---

## 6. Build phases (suggested order for Claude Code)

1. **Backend first:** stand up the cloud function, wire the sports-data API call, implement the rubric scoring function (shared spec, points 1–3), add the daily cache, add the two LLM calls (hook + stakes) with the Q1/Q2 score-hiding rule enforced server-side.
2. **Live polling:** add the frequent-refresh path for in-progress games, updating period/clock always, and score/tier only from end-of-Q3.
3. **Android app:** Kotlin + Jetpack Compose client that fetches the backend JSON, ports the tier/scoring constants, implements the day-tab UI, blur-to-reveal hook interaction, and full-breakdown expandable section — visually matching the existing JSX prototype's dark bold styling.
4. **Testing pass:** verify against a known live game window and a known completed day to confirm spoiler rules hold (no score before Q3 end, no result in hooks).
5. **iOS port (later):** same JSON contract, same rubric constants, Swift/SwiftUI client mirroring the Android UI.

---

## 7. Explicitly out of scope for v1

- Push notifications (feature discussed but deferred).
- Custom domain (using free auto-generated cloud URL for now).
- Any ESPN (or other broadcaster) branding, assets, or copied layouts — style reference is generic "dark bold sports UI," not a specific product's IP.

---

## 8. Account/ownership responsibilities (not part of the code build)

These require the user's own identity/payment and cannot be created by Claude Code:
- Google Play Developer account ($25 one-time)
- Apple Developer account ($99/year, only needed when iOS build begins)
- Ownership of the GitHub account and cloud provider account the code/backend deploys under

Claude Code should assume these accounts exist and ask for the relevant IDs/credentials to deploy into, rather than attempting to create them.
