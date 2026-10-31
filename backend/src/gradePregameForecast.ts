// Marks the pre-game forecast's homework. Run it whenever you want to know
// whether the outlook index is worth anything:
//
//   cd backend && npx tsx src/gradePregameForecast.ts
//
// Reports RANK correlation (Spearman), not Pearson, because the outlook index
// is on an arbitrary scale - see pregameForecastV1's doc comment. The only
// claim it could possibly make is "games I rate higher tend to score higher",
// and rank correlation is exactly that claim and nothing more.
//
// How to read the output, so this doesn't get over-interpreted the way the
// matchup idea nearly was:
//
//   rho ~ 0.0        no signal. Expected, honestly, and the useful answer.
//   rho ~ 0.1-0.2    real but weak; worth a v2, not worth showing a user.
//   rho > 0.3        genuinely predictive for this kind of problem. Then the
//                    conversation about surfacing it in the app can start.
//
// The "95% null band" column is the important guard. With n games, pure noise
// still produces a non-zero rho - roughly +/-1.96/sqrt(n-1). If the measured
// rho sits inside that band it is indistinguishable from random, no matter
// how suggestive the sign looks. Early in collection n is small and the band
// is wide, which is why this will say "not yet" for a while.
import { allScoredGamesWithForecast } from "./gameStore";

function spearman(pairs: Array<{ x: number; y: number }>): number {
  const rank = (vals: number[]): number[] => {
    const order = vals.map((v, i) => ({ v, i })).sort((a, b) => a.v - b.v);
    const ranks = new Array<number>(vals.length);
    let i = 0;
    while (i < order.length) {
      // Ties share the average of the ranks they span - forecasts are rounded
      // integers so ties are common, and ignoring them would bias rho.
      let j = i;
      while (j + 1 < order.length && order[j + 1].v === order[i].v) j++;
      const avg = (i + j) / 2 + 1;
      for (let k = i; k <= j; k++) ranks[order[k].i] = avg;
      i = j + 1;
    }
    return ranks;
  };

  const rx = rank(pairs.map((p) => p.x));
  const ry = rank(pairs.map((p) => p.y));
  const n = pairs.length;
  const mx = rx.reduce((s, v) => s + v, 0) / n;
  const my = ry.reduce((s, v) => s + v, 0) / n;
  let num = 0;
  let dx = 0;
  let dy = 0;
  for (let i = 0; i < n; i++) {
    const a = rx[i] - mx;
    const b = ry[i] - my;
    num += a * b;
    dx += a * a;
    dy += b * b;
  }
  return dx === 0 || dy === 0 ? 0 : num / Math.sqrt(dx * dy);
}

const rows = allScoredGamesWithForecast();
if (rows.length === 0) {
  console.log("No graded games yet: no game has both a pre-game snapshot and a final score.");
  console.log("Expected until snapshots have been collected for games that have since finished.");
  process.exit(0);
}

const byLeague = new Map<string, typeof rows>();
for (const r of rows) {
  const key = `${r.leagueGroup}|${r.preForecastVersion ?? "?"}`;
  if (!byLeague.has(key)) byLeague.set(key, []);
  byLeague.get(key)!.push(r);
}

console.log(`\nGraded games: ${rows.length}\n`);
const summary: Array<Record<string, string | number>> = [];
for (const [key, games] of [...byLeague.entries()].sort()) {
  const [leagueGroup, version] = key.split("|");
  const rho = spearman(games.map((g) => ({ x: g.preForecast!, y: g.score! })));
  const band = 1.96 / Math.sqrt(Math.max(2, games.length) - 1);
  summary.push({
    league: leagueGroup,
    version,
    n: games.length,
    rho: rho.toFixed(3),
    "95% null band": `+/-${band.toFixed(3)}`,
    verdict: games.length < 30 ? "too early" : Math.abs(rho) < band ? "indistinguishable from noise" : rho > 0 ? "SIGNAL" : "inverted",
  });
}
console.table(summary);

// Bucketed view: the thing to look for is monotonicity down the avg_score
// column. A real signal makes it climb; a dead one makes it wander.
for (const [key, games] of [...byLeague.entries()].sort()) {
  if (games.length < 30) continue;
  const sorted = [...games].sort((a, b) => a.preForecast! - b.preForecast!);
  const q = Math.ceil(sorted.length / 4);
  console.log(`\n${key} - by forecast quartile:`);
  const buckets: Array<Record<string, string | number>> = [];
  for (let i = 0; i < 4; i++) {
    const slice = sorted.slice(i * q, (i + 1) * q);
    if (slice.length === 0) continue;
    buckets.push({
      quartile: `Q${i + 1}`,
      "forecast range": `${slice[0].preForecast}-${slice[slice.length - 1].preForecast}`,
      n: slice.length,
      avg_score: (slice.reduce((s, g) => s + g.score!, 0) / slice.length).toFixed(1),
    });
  }
  console.table(buckets);
}
