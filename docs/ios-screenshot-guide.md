# App Store screenshots — capture guide

Everything James needs to shoot the App Store Connect screenshots on real
hardware, plus what happens to the files afterwards.

Companion to `docs/ios-app-store-listing.md` (the text copy) and
`docs/ios-testflight-setup.md` (certs/profiles/upload).

---

## The short version

1. Borrow **any** iPhone, install the TestFlight build on it.
2. Take the **6 iPhone shots** listed below, portrait, in order.
3. Take the **same 6 shots on the iPad** (you already have it).
4. Send me all 12 files. **Do not resize or crop them yourself** — I'll
   rescale to Apple's exact pixel dimensions.

That's it. The rest of this doc is the detail behind those four lines.

---

## Why "any iPhone" is fine (the gotcha, solved)

App Store Connect only accepts screenshots at **exact pixel dimensions**.
It will reject a file that is one pixel off. The two slots that matter:

| Slot | Required pixels (portrait) | Device that shoots it natively |
|---|---|---|
| iPhone 6.9" | **1290 × 2796** | iPhone 15/16/17 Pro Max |
| iPad 13" | **2048 × 2732** | iPad Pro 12.9"/13" |

Both slots are **mandatory** for this app, because `TARGETED_DEVICE_FAMILY`
is `"1,2"` — it ships as a universal iPhone + iPad binary, so Apple wants
both families covered.

You almost certainly won't borrow a Pro Max, and your old iPad isn't a 13"
Pro. That's fine, because **every modern iPhone shares the same 19.5:9
aspect ratio and every iPad shares 4:3**:

- iPhone 14 / 15 / 16 (non-Max): 1179 × 2556 → 19.51:9
- iPhone 6.9" target: 1290 × 2796 → 19.50:9
- Any iPad portrait: 1536 × 2048 → 3:4
- iPad 13" target: 2048 × 2732 → 3:4

So a straight proportional rescale lands on Apple's exact numbers with no
crop, no distortion, no letterboxing. I'll do that with Pillow — the same
tool used to flatten the icon alpha channels back in the 09-20 upload
fight. Send me the raw files.

**What would actually break this:** shooting in landscape, using an iPhone
SE / iPhone 8 (16:9, wrong ratio — visible distortion on rescale), or
cropping the status bar off. Avoid those three and anything works.

---

## Before you shoot

- [ ] Install the latest TestFlight build (currently **build 11**).
- [ ] **Settings → Rubric Weights**: leave at defaults. Screenshots should
      show the shipping experience, not a tuned one.
- [ ] Turn **Player Hater Mode OFF** (Settings → About → tap version 8×
      toggles it). The roast lines are a fun easter egg, not something to
      put in front of an App Store reviewer.
- [ ] Put the phone in **Do Not Disturb** — a notification banner sliding
      in mid-shot means reshooting.
- [ ] **Battery above 80%**, and ideally full signal. Apple doesn't require
      a clean status bar, but a 12%-battery screenshot looks unloved.
- [ ] Pick a day with **real finished games across several leagues**. An
      empty schedule makes for a terrible first impression. Best bets: any
      day in the NBA/NHL regular season, or an NFL Sunday.

---

## The 6 shots

Order matters — App Store Connect shows them in the order uploaded, and
shot 1 is the only one most people ever see.

### Shot 1 — Games tab, tiers visible
**Tab:** Games · **League:** ALL (or NBA if ALL looks sparse)
**State:** a day with a good spread of tiers — at least one **Instant
Classic** and one **Worth Your Time** visible without scrolling.
**Why:** this is the entire product in one image. The tier badges and the
colour-coded card borders are the thing that makes someone understand the
app in two seconds. Scroll so a high tier is near the top, not the bottom.

### Shot 2 — Game detail, Breakdown tab
**Tab:** Games → tap a finished **Instant Classic** tile → **Breakdown**
**State:** the rubric breakdown rows showing what earned the score.
**Why:** answers "is this just vibes?" — shows there's a real scoring
system underneath. Pick a game with a dramatic breakdown (big comeback or
an OT finish) rather than a flat one.

### Shot 3 — Day navigation
**Tab:** Games, with the **Yesterday / Today / Tomorrow** strip visible
**State:** ideally mid-swipe is impossible to catch, so just make sure the
day strip and the calendar + sort icons are clearly in frame at the top.
**Why:** this is brand new (built 09-20/21) and it's what makes the app a
daily habit rather than a one-off lookup.

### Shot 4 — Standings
**Tab:** Standings · **League:** NBA or NFL (most recognisable tables)
**Why:** shows the app isn't a one-trick scoring gimmick — there's real
league data in here.

### Shot 5 — Favorites
**Tab:** Favorites
**State:** **have 3–4 real teams favorited first**, across at least two
leagues, so the screen isn't empty. Include a team with a recognisable
logo.
**Why:** personalisation. An empty Favorites screen is the single worst
screenshot you could ship.

### Shot 6 — Stats or News
**Tab:** whichever looks better on the day
**Why:** rounds out the "there's more in here than scores" story.

**Optional 7th:** the Alerts settings screen — but only once alerts
actually work on iOS (I'm building that now). Don't shoot it yet.

---

## Spoiler-safety check before you send

The app's whole pitch is *spoiler-safe*. Make sure no screenshot shows a
**final score** or a **winner** unless that game's result is deliberately
revealed. Tier badges and watchability scores are fine — that's the
product. Actual scorelines are not.

Worth a slow look at shot 2 in particular: the Breakdown tab can surface
result-shaped detail depending on the game.

---

## How to take a screenshot

- **iPhone (Face ID):** Side button + Volume Up together.
- **iPhone (Touch ID):** Home + Side button.
- **iPad (no Home button):** Top button + Volume Up.
- **iPad (Home button):** Home + Top button.

Then send the files to me however's easiest — the Drive phone-app folder
works, or just attach them.

---

## What I do with them

1. Verify each file's real pixel dimensions (parsing the PNG header, not
   trusting the filename).
2. Proportionally rescale: iPhone shots → **1290 × 2796**, iPad shots →
   **2048 × 2732**.
3. Strip any alpha channel — Apple rejects alpha on screenshots the same
   way it rejected it on the 1024×1024 marketing icon.
4. Write them to `ios/screenshots/` ready for upload.

The upload itself is yours — App Store Connect → the app → the version →
Previews and Screenshots, drag into the 6.9" iPhone and 13" iPad slots.

---

## Open item

Apple also wants a **1024 × 1024 marketing icon** with no alpha. That
already exists and is already flattened (09-20 icon work) — no action
needed, noting it here so it isn't re-litigated.
