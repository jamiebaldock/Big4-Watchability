// Record parsing is the part worth testing: NHL's three-part "7-3-1" is the
// one format a W-L parser mangles silently, and silently-wrong is the whole
// risk with a dataset nobody reads for a season.
import assert from "node:assert";
import { parseRecord, pregameForecastV1 } from "./pregameForecast";

// --- real strings, copied from live ESPN scoreboards on 2026-10-28 ---
const nba = parseRecord("2-2")!;
assert.strictEqual(nba.winPct, 0.5, "NBA 2-2");

const nfl = parseRecord("5-1")!;
assert.ok(Math.abs(nfl.winPct - 5 / 6) < 1e-9, "NFL 5-1");

const mlb = parseRecord("98-64")!;
assert.ok(Math.abs(mlb.winPct - 98 / 162) < 1e-9, "MLB 98-64");

// The one that matters: 7-3-1 is 11 games, not 10, and the OT loss is worth
// half a win (= the league's own points percentage). A naive two-part parse
// would read 0.700 here.
const nhl = parseRecord("7-3-1")!;
assert.strictEqual(nhl.otLosses, 1, "NHL OT losses parsed");
assert.ok(Math.abs(nhl.winPct - 7.5 / 11) < 1e-9, `NHL 7-3-1 -> ${nhl.winPct}`);
assert.ok(nhl.winPct < 0.7, "NHL OT loss must drag the pct below a bare W/L read");

// --- refusals: a null snapshot is honest, a fabricated 0.000 is not ---
assert.strictEqual(parseRecord("0-0"), null, "season opener carries no information");
assert.strictEqual(parseRecord("0-0-0"), null, "NHL season opener likewise");
assert.strictEqual(parseRecord(undefined), null, "missing record");
assert.strictEqual(parseRecord(""), null, "empty record");
assert.strictEqual(parseRecord("not-a-record"), null, "garbage");
assert.strictEqual(parseRecord("1-2-3-4"), null, "too many parts");
assert.strictEqual(parseRecord("5"), null, "too few parts");

// --- forecast ordering (the only property it actually claims) ---
const evenAndGood = pregameForecastV1({ awayWinPct: 0.7, homeWinPct: 0.7, isPostseason: false });
const evenAndBad = pregameForecastV1({ awayWinPct: 0.3, homeWinPct: 0.3, isPostseason: false });
const mismatch = pregameForecastV1({ awayWinPct: 0.9, homeWinPct: 0.1, isPostseason: false });

assert.ok(evenAndGood > evenAndBad, "two good even teams beat two bad even teams");
assert.ok(evenAndGood > mismatch, "an even matchup beats a mismatch of the same average quality");
assert.ok(
  pregameForecastV1({ awayWinPct: 0.5, homeWinPct: 0.5, isPostseason: true }) >
    pregameForecastV1({ awayWinPct: 0.5, homeWinPct: 0.5, isPostseason: false }),
  "postseason bump applies"
);

// The regression the first live run caught: two winless teams are perfectly
// even, and must NOT collect the full evenness payoff for it. Pinned against
// a real pair of rows (Kings 0-4 at Pelicans 0-3, 2026-10-28), which scored
// 60/100 under the original additive formula.
const twoWinless = pregameForecastV1({ awayWinPct: 0, homeWinPct: 0, isPostseason: false });
assert.ok(twoWinless < 30, `two winless teams must rate low, got ${twoWinless}`);
assert.ok(twoWinless < evenAndBad, "winless is worse than merely bad");
assert.ok(
  twoWinless < pregameForecastV1({ awayWinPct: 0.6, homeWinPct: 0.4, isPostseason: false }),
  "a slightly uneven pair of decent teams beats a perfectly even pair of awful ones"
);

// Stays in range at both extremes, including with the postseason bump on top.
for (const p of [0, 1]) {
  for (const isPostseason of [false, true]) {
    const v = pregameForecastV1({ awayWinPct: p, homeWinPct: 1 - p, isPostseason });
    assert.ok(v >= 0 && v <= 100, `in range: ${v}`);
  }
}
assert.strictEqual(pregameForecastV1({ awayWinPct: 1, homeWinPct: 1, isPostseason: true }), 100, "clamped at the top");

console.log("pregameForecast tests passed");
