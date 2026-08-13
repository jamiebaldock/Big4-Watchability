# NBA Watchability App — Visual Design Prompt

Design a dark, bold, sports-broadcast-style mobile app UI for an NBA "watchability" guide. Style genre reference: the general look of dark-mode sports score apps (e.g. ESPN's dark mode, Bleacher Report, The Athletic) — high-contrast, condensed, built for scanning a list of games fast. Do NOT use any ESPN (or other broadcaster) logos, wordmarks, exact color values, or copied layouts — this is a genre reference only, not a copy.

**Palette**
- Dark navy/charcoal base, roughly `#101418` to `#1A2027`
- High-contrast off-white text (`#E8EAED`) for primary content
- Muted gray-blue (`#8A94A0`) for secondary/metadata text
- Saturated accent colors reserved strictly for status meaning, not decoration:
  - Red/orange for a "LIVE" indicator
  - Gold/orange (`#FFB020`-ish) for the top "🔥 Instant Classic" tier
  - Blue (`#6FA8DC`-ish) for the "👍 Solid" tier
  - Muted gray (`#7A8592`) for the "😴 Skippable" tier
  - Warm red (`#FF5C33`-ish) for the top tier's icon/border if distinct from LIVE

**Typography**
- Bold, condensed weight for team matchup names — these are the visual anchor of each card
- Clear hierarchy: team names > tier badge > hook/summary text > metadata (time, quarter, etc.)
- Monospace or tabular numerals for anything numeric (scores, clocks, token counts) to keep alignment tidy

**Layout**
- Day-by-day tabs or horizontal swipe between days — not one long infinite scroll, not a calendar drill-down
- Each day's view is a vertical list of game cards in schedule order by default
- A toggle exists to sort "best first" instead of schedule order, and a separate toggle to reveal raw numeric scores instead of tier badges only

**Game card anatomy**
- Header row: away team @ home team (bold), with the tier badge as a pill/tag on the right — medium prominence: a clear icon + short label (e.g. "🔥 INSTANT CLASSIC"), not oversized, not icon-only
- Below that: a one-line "hook" sentence, rendered blurred/obscured until tapped — spoiler-free, never reveals winner or score
- A secondary, collapsed "full breakdown" section users can expand for more detail (comeback size, OT, buzzer-beater flag) — still never the winner or final score
- For upcoming games: replace the tier badge with the scheduled tip-off time in the user's local timezone
- For live games: replace the tier badge with a pulsing "LIVE" indicator plus current period (Q1–Q4, OT1, OT2...) and game clock; the tier badge itself only appears once the game reaches the end of the 3rd quarter, staying hidden entirely during Q1–Q2

**Overall feel**
- Should read as confident and information-dense but not cluttered — like glancing at a scoreboard, not reading a report
- The blurred/obscured hook text should feel like an intentional, tappable interaction (e.g. a soft blur with a subtle "tap to reveal" affordance), not a bug or placeholder
