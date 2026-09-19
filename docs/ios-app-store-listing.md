# App Store Connect listing copy — draft

Character limits are Apple's hard limits (the field will reject anything
longer). Adjust wording freely, just stay under each count.

## App name (30 char max)

**Big4 Watchability** (18 chars)

Same as the Play Store name — no reason to diverge.

## Subtitle (30 char max)

**Know which games to watch** (27 chars)

Alternates if you want options:
- "Spoiler-safe game ratings" (26 chars)
- "Which games are worth it?" (26 chars)

## Promotional text (170 char max, editable without a new review)

"See which NBA, WNBA, MLB, NFL, and NHL games are actually worth watching — rated for excitement, spoiler-free until you're ready to know." (140 chars)

## Description (4000 char max)

Big4 Watchability rates every NBA, WNBA, MLB, NFL, and NHL game for how
exciting it actually was — so you never waste time on a blowout or miss a
classic.

**HOW IT WORKS**
Every finished game gets a Watchability Score built from what actually
makes a game exciting: close margins, comebacks, lead changes, clutch
finishes, buzzer-beaters, overtime, and standout individual performances.
Scores land in one of four tiers — Instant Classic, Worth Your Time, Solid,
or Skippable — shown right on the game tile. Nothing about how a game turns
out is shown until you ask for it.

**FIVE LEAGUES, ONE APP**
Track NBA, WNBA, MLB, NFL, and NHL games side by side. Each league is scored
on its own scale, calibrated separately against real completed games rather
than one generic formula.

**SPOILER-SAFE BY DESIGN**
Scores and outcomes stay hidden until the fourth quarter/final period, or
until you choose to reveal them. Browse the schedule, check who's playing,
and see a tier badge — without ever seeing a live score you didn't ask for.

**FAVORITES & ALERTS**
Follow your favorite teams and players across every league. Get a
notification shortly before their games start, plus an alert if the score
swings late in a close one.

**HISTORY & ALL-TIME**
Browse a curated archive of the best games from recent seasons, sortable by
date or score. All-Time narrows it further to each league's top 20 games
ever — ranked, not just a cutoff.

**CUSTOMIZE THE RATING**
Every league's Watchability Score is a weighted mix of factors like margin,
comebacks, and clutch finishes. Adjust any factor up or down, per league,
to match what makes a game exciting to you.

Big4 Watchability is an independent app and is not affiliated with,
endorsed by, or sponsored by the NBA, WNBA, MLB, NFL, NHL, or any of their
teams.

(≈1,650 chars — plenty of headroom under the 4000 limit if you want to add more)

## Keywords (100 char max, comma-separated, no spaces after commas to save characters)

`sports,scores,nba,nfl,mlb,nhl,wnba,basketball,football,baseball,hockey,highlights,spoiler free`

(96 chars — Apple's keyword field doesn't show to users, purely for search indexing)

## What's New (first release — 4000 char max, same field used for update notes later)

"Welcome to Big4 Watchability! Track NBA, WNBA, MLB, NFL, and NHL games,
see which ones are actually worth watching, and never get spoiled on a
score you didn't ask for."

## Support & marketing URLs

- **Support URL** (required): `https://jamiebaldock.github.io/Big4-Watchability/support.html`
  — built 2026-09-19 (`docs/support.html`), contact email + a few FAQ
  entries (spoiler-safe scoring, missing highlights, alerts, Favorites
  persistence). Live once pushed to `main` (GitHub Pages serves `docs/`).
- **Marketing URL** (optional): can leave blank.
- **Privacy Policy URL** (required): `https://jamiebaldock.github.io/Big4-Watchability/privacy-policy.html`
  — already live, already used for the Play Store listing. Updated
  2026-09-19 to drop an inaccurate "Remove Ads IAP available" claim (never
  built, on either platform) and to split the ads/push-notification
  sections into Android-only vs. iOS (iOS currently has neither), so the
  same page is accurate for both platforms' App Store listings.

## Age rating questionnaire

Should land as **4+** — no objectionable content, no user-generated
content, no gambling. Sports league names/logos are not a factor in
Apple's age rating (that's the separate Guideline 5.2 IP question, not
age-appropriateness).

## App Privacy ("nutrition label") — Data Types Collected

Per the 2026-09-05 code audit (BACKLOG.md F8): **no AdMob, no analytics, no
tracking SDK on iOS.** The only network traffic is to the app's own backend
(game data) and YouTube's embed player (highlights). Realistic answers to
Apple's questionnaire:

- **Data Not Linked to You**: none expected — no accounts, no user
  identifiers collected.
- **Data Used to Track You**: No.
- Checked the actual iOS source for this doc (not assumed): no Firebase, no
  FCM, no APNs/PushKit code exists anywhere in `ios/` — Alerts push was
  never built on iOS (it's the one feature gap noted in the iOS memory,
  blocked on exactly the Apple Developer account this doc's setup depends
  on). So there's no push-token collection to account for yet either.
  Likely answer to the whole questionnaire really is just **"Data Not
  Collected."** Re-check this section if/when Alerts push gets built later —
  adding APNs at that point would need a real answer here, not this one.

## Screenshots

Needed sizes (as of 2026, subject to Apple changing requirements): 6.9"
display (iPhone 16 Pro Max class) and 13" iPad display if keeping iPad
support (`TARGETED_DEVICE_FAMILY` is currently `1,2` = both). Can't produce
these without actually running the app on a device/simulator — this is
blocked on the same "never visually verified" gap as everything else
iOS-side. Once a TestFlight build exists, screenshots come from there.
