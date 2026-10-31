// Cup labelling, pinned against the exact note headlines ESPN really sends.
// Every string below was counted off live scoreboards (Nov-Dec 2024+2025 for
// the NBA, the 2025 season for the WNBA) rather than invented - the NBA's
// knockout rounds use " - " before the round while its Championship does
// not, and the WNBA's group games carry no round qualifier at all, so this
// is easy to break with a plausible-looking refactor.
import assert from "node:assert";
import { deriveCompetitionLabel, deriveSeasonStage } from "./gameMapper";
import type { EspnEvent } from "./espnClient";

function eventWith(headline: string | null, slug = "regular-season"): EspnEvent {
  return {
    competitions: [{ notes: headline ? [{ type: "event", headline }] : [] }],
    season: { slug },
  } as unknown as EspnEvent;
}

// --- NBA, with the sponsor name and the round ---
const nba: Array<[string, string]> = [
  ["NBA Cup - Group Play", "Emirates NBA Cup: Group Play"],
  ["NBA Cup - Quarterfinals", "Emirates NBA Cup: Quarterfinals"],
  ["NBA Cup - Semifinals", "Emirates NBA Cup: Semifinals"],
  ["NBA Cup Championship", "Emirates NBA Cup: Championship"],
];
for (const [headline, expected] of nba) {
  assert.strictEqual(deriveSeasonStage(eventWith(headline)), expected, headline);
  assert.strictEqual(deriveCompetitionLabel(eventWith(headline), "nba"), `NBA - ${expected}`, headline);
}

// --- WNBA keeps its own competition, and does NOT get "Emirates" ---
assert.strictEqual(deriveSeasonStage(eventWith("WNBA Commissioner's Cup")), "Commissioner's Cup");
assert.strictEqual(
  deriveSeasonStage(eventWith("WNBA Commissioner's Cup Championship")),
  "Commissioner's Cup: Championship"
);
// "WNBA - WNBA Commissioner's Cup" would be the obvious mistake here.
assert.strictEqual(
  deriveCompetitionLabel(eventWith("WNBA Commissioner's Cup"), "wnba"),
  "WNBA - Commissioner's Cup"
);

// --- ordinary games are untouched by any of it ---
assert.strictEqual(deriveSeasonStage(eventWith(null)), "Regular Season");
assert.strictEqual(deriveSeasonStage(eventWith(null, "preseason")), "Preseason");
assert.strictEqual(deriveSeasonStage(eventWith(null, "play-in-season")), "Play-In Tournament");
// All-Star is checked before the Cup branch and must stay that way.
assert.strictEqual(deriveSeasonStage(eventWith("NBA All-Star - Championship")), "All-Star");

console.log("gameMapper tests passed");
