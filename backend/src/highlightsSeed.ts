// One-time manual seed: video IDs confirmed by eye (the user pasted real
// YouTube links, matched here to their exact ESPN event by team names/date)
// rather than found via search.list - lets specific games show a working
// highlights link immediately without spending any of the 100/day search
// quota. Safe to run on every startup: gameStore.setHighlightsFromSeed only
// ever writes when yt_video_id is still NULL, so a genuine search result
// already on file is never clobbered - the guard lives in the store itself
// now, not in this file's own bookkeeping. Uses the seed-specific setter
// (not setHighlights) so these manually-confirmed matches don't get folded
// into the learned upload-lag schedule as if they were real search
// discoveries - they weren't found via the natural wait-and-search process
// at all, and doing so would badly skew future scheduling.
import { BasketballLeagueGroup, getGamesForDate } from "./gamesService";
import { getGame, setHighlightsFromSeed } from "./gameStore";
import { getMlbGamesForDate } from "./mlbGamesService";

type SeedLeagueGroup = BasketballLeagueGroup | "mlb";

interface SeedEntry {
  date: string; // YYYY-MM-DD, just to know which schedule fetch surfaces this event
  leagueGroup: SeedLeagueGroup;
  eventId: string;
  videoId: string;
}

const SEED_ENTRIES: SeedEntry[] = [
  // WNBA
  { date: "2026-07-09", leagueGroup: "wnba", eventId: "401857051", videoId: "bvxI5XYci-c" }, // Seattle Storm at Atlanta Dream
  { date: "2026-07-09", leagueGroup: "wnba", eventId: "401857052", videoId: "HTuwygyES0I" }, // Indiana Fever at Phoenix Mercury
  { date: "2026-07-09", leagueGroup: "wnba", eventId: "401857053", videoId: "_QRHMeF4MNo" }, // Las Vegas Aces at Portland Fire
  { date: "2026-07-10", leagueGroup: "wnba", eventId: "401857054", videoId: "sbN0es8-4Cs" }, // Golden State Valkyries at Connecticut Sun
  { date: "2026-07-10", leagueGroup: "wnba", eventId: "401857055", videoId: "GGXVuP_qmf8" }, // Dallas Wings at Toronto Tempo
  { date: "2026-07-10", leagueGroup: "wnba", eventId: "401857056", videoId: "q8R3oBD_2NM" }, // Chicago Sky at Los Angeles Sparks
  { date: "2026-07-11", leagueGroup: "wnba", eventId: "401857057", videoId: "thZxZ18wqnI" }, // New York Liberty at Minnesota Lynx
  { date: "2026-07-11", leagueGroup: "wnba", eventId: "401857058", videoId: "ufAid0Dp33M" }, // Phoenix Mercury at Las Vegas Aces
  { date: "2026-07-11", leagueGroup: "wnba", eventId: "401857059", videoId: "BljnCJv7TAg" }, // Portland Fire at Atlanta Dream

  // NBA Summer League (Las Vegas)
  { date: "2026-07-10", leagueGroup: "nba", eventId: "401879489", videoId: "TMzXSZJlato" }, // Chicago Bulls at Memphis Grizzlies
  { date: "2026-07-10", leagueGroup: "nba", eventId: "401881832", videoId: "vak4ZOGks7U" }, // Boston Celtics at Toronto Raptors
  { date: "2026-07-10", leagueGroup: "nba", eventId: "401881833", videoId: "Fd3qGkD-exI" }, // Oklahoma City Thunder at Los Angeles Lakers
  { date: "2026-07-10", leagueGroup: "nba", eventId: "401881834", videoId: "yZMVnmA9iWk" }, // Portland Trail Blazers at Phoenix Suns
  { date: "2026-07-11", leagueGroup: "nba", eventId: "401881835", videoId: "ScKEDHE1Rcg" }, // Miami Heat at Orlando Magic
  { date: "2026-07-11", leagueGroup: "nba", eventId: "401881836", videoId: "C3k2NAsQaRE" }, // New Orleans Pelicans at Charlotte Hornets
  { date: "2026-07-11", leagueGroup: "nba", eventId: "401881837", videoId: "km9Ml7-hOh4" }, // Indiana Pacers at Philadelphia 76ers
  { date: "2026-07-11", leagueGroup: "nba", eventId: "401881838", videoId: "jFiM59ru6J0" }, // New York Knicks at San Antonio Spurs
  { date: "2026-07-11", leagueGroup: "nba", eventId: "401881839", videoId: "oapzGvKg1lE" }, // Denver Nuggets at Minnesota Timberwolves
  { date: "2026-07-11", leagueGroup: "nba", eventId: "401881840", videoId: "ngg9qm7CbZ4" }, // Atlanta Hawks at Brooklyn Nets

  // MLB
  { date: "2026-07-19", leagueGroup: "mlb", eventId: "401816184", videoId: "5Nb08y6UgLA" }, // St. Louis Cardinals at Arizona Diamondbacks (F/10)

  // MLB 2025 History-tab backfill (added 2026-09-08). The rated 2025-season
  // games surfacing on the History tab had no highlights link, because MLB's
  // automated highlights search is built but not wired in (mlbGamesService.ts).
  // Video IDs found by search and each verified against the game's ESPN event
  // data (teams + final score + local game date). Dates below are the local
  // (US) game date - how ESPN's scoreboard buckets the event and how the MLB
  // channel titles its upload - which for several night games is one day
  // earlier than the UTC date gameStore holds them under.
  { date: "2025-04-04", leagueGroup: "mlb", eventId: "401695020", videoId: "u6q_TYuw0qU" }, // Seattle Mariners at San Francisco Giants
  { date: "2025-04-18", leagueGroup: "mlb", eventId: "401695202", videoId: "Za4smeV-CJ8" }, // Arizona Diamondbacks at Chicago Cubs
  { date: "2025-04-22", leagueGroup: "mlb", eventId: "401695255", videoId: "zn_KjpuEWuI" }, // Los Angeles Dodgers at Chicago Cubs
  { date: "2025-04-27", leagueGroup: "mlb", eventId: "401695316", videoId: "b1kzFE0Afu0" }, // New York Mets at Washington Nationals
  { date: "2025-04-30", leagueGroup: "mlb", eventId: "401695353", videoId: "NA47LLD64Us" }, // Boston Red Sox at Toronto Blue Jays
  { date: "2025-05-05", leagueGroup: "mlb", eventId: "401764534", videoId: "QZifqTAzfY8" }, // Seattle Mariners at Athletics
  { date: "2025-05-13", leagueGroup: "mlb", eventId: "401695528", videoId: "R8nbQkNiNKE" }, // Boston Red Sox at Detroit Tigers
  { date: "2025-05-17", leagueGroup: "mlb", eventId: "401695578", videoId: "uVjDvhB0EJ0" }, // Atlanta Braves at Boston Red Sox
  { date: "2025-05-22", leagueGroup: "mlb", eventId: "401695654", videoId: "uOdjdcaas5s" }, // San Diego Padres at Toronto Blue Jays
  { date: "2025-05-23", leagueGroup: "mlb", eventId: "401695663", videoId: "rq4zu_AOG3c" }, // Milwaukee Brewers at Pittsburgh Pirates
  { date: "2025-05-28", leagueGroup: "mlb", eventId: "401695736", videoId: "ZhSWLfJvrPg" }, // Boston Red Sox at Milwaukee Brewers
  { date: "2025-05-31", leagueGroup: "mlb", eventId: "401695776", videoId: "MuwK2VI4M0g" }, // Minnesota Twins at Seattle Mariners
  { date: "2025-06-21", leagueGroup: "mlb", eventId: "401696053", videoId: "kvONO06-Dws" }, // Cincinnati Reds at St. Louis Cardinals
  { date: "2025-07-10", leagueGroup: "mlb", eventId: "401696305", videoId: "cdysB9m1seo" }, // Seattle Mariners at New York Yankees
  { date: "2025-07-18", leagueGroup: "mlb", eventId: "401696363", videoId: "wozHtA4_7ZM" }, // Kansas City Royals at Miami Marlins
  { date: "2025-08-01", leagueGroup: "mlb", eventId: "401696553", videoId: "m1zhoyyeFL0" }, // New York Yankees at Miami Marlins
  { date: "2025-08-01", leagueGroup: "mlb", eventId: "401696556", videoId: "MA84Qcx-VvQ" }, // Pittsburgh Pirates at Colorado Rockies (17-16)
  { date: "2025-08-10", leagueGroup: "mlb", eventId: "401696676", videoId: "8k4LyJPqP-g" }, // New York Mets at Milwaukee Brewers
  { date: "2025-08-11", leagueGroup: "mlb", eventId: "401696685", videoId: "1raOQSofDis" }, // Arizona Diamondbacks at Texas Rangers
  { date: "2025-08-19", leagueGroup: "mlb", eventId: "401696789", videoId: "adRLXdX8FQI" }, // Chicago White Sox at Atlanta Braves
  { date: "2025-08-27", leagueGroup: "mlb", eventId: "401696900", videoId: "eGdWy1HLs-g" }, // Minnesota Twins at Toronto Blue Jays
  { date: "2025-09-01", leagueGroup: "mlb", eventId: "401696972", videoId: "rPyhBPpMGAA" }, // Atlanta Braves at Chicago Cubs
  { date: "2025-09-12", leagueGroup: "mlb", eventId: "401697117", videoId: "o0vjVaE5XeE" }, // Arizona Diamondbacks at Minnesota Twins
  { date: "2025-09-13", leagueGroup: "mlb", eventId: "401697133", videoId: "JNa1SaML-5U" }, // St. Louis Cardinals at Milwaukee Brewers
  { date: "2025-09-28", leagueGroup: "mlb", eventId: "401697330", videoId: "CowYwD0xVCI" }, // Texas Rangers at Cleveland Guardians
  { date: "2025-10-27", leagueGroup: "mlb", eventId: "401809299", videoId: "kipXGXpfZ2E" }, // Toronto Blue Jays at Los Angeles Dodgers (World Series Game 3, 18 innings)

  // MLB 2024 History-tab backfill (added 2026-09-08). Same as the 2025 block
  // above - found by search, verified against each game's ESPN event data,
  // dated by local (US) game date. One rated 2024 game is deliberately not
  // seeded: Royals at Tigers 2024-08-03 (401570131 - no official MLB-channel
  // upload found).
  { date: "2024-04-06", leagueGroup: "mlb", eventId: "401568584", videoId: "ACN6_fiKmdI" }, // Arizona Diamondbacks at Atlanta Braves
  { date: "2024-04-08", leagueGroup: "mlb", eventId: "401568616", videoId: "eTBWF8GHXbI" }, // Chicago Cubs at San Diego Padres
  { date: "2024-04-10", leagueGroup: "mlb", eventId: "401568644", videoId: "SNlqqjYcna0" }, // Chicago White Sox at Cleveland Guardians
  { date: "2024-04-14", leagueGroup: "mlb", eventId: "401568701", videoId: "9JLSmsrpxIo" }, // New York Yankees at Cleveland Guardians
  { date: "2024-04-16", leagueGroup: "mlb", eventId: "401568723", videoId: "VNieypNAa34" }, // Los Angeles Angels at Tampa Bay Rays
  { date: "2024-04-16", leagueGroup: "mlb", eventId: "401568725", videoId: "oVqZnkQLXHY" }, // Chicago Cubs at Arizona Diamondbacks
  { date: "2024-04-25", leagueGroup: "mlb", eventId: "401568851", videoId: "aF-3YwImOeU" }, // San Diego Padres at Colorado Rockies
  { date: "2024-04-26", leagueGroup: "mlb", eventId: "401568861", videoId: "ftSzo6pMNcE" }, // New York Yankees at Milwaukee Brewers
  { date: "2024-04-27", leagueGroup: "mlb", eventId: "401568881", videoId: "6h_2ZDoNn4c" }, // Tampa Bay Rays at Chicago White Sox
  { date: "2024-04-30", leagueGroup: "mlb", eventId: "401568914", videoId: "HpPJwEH7THU" }, // Colorado Rockies at Miami Marlins
  { date: "2024-04-30", leagueGroup: "mlb", eventId: "401568913", videoId: "TcroXD0kEMY" }, // Cleveland Guardians at Houston Astros
  { date: "2024-05-02", leagueGroup: "mlb", eventId: "401568940", videoId: "NB9_a2aQbT8" }, // Chicago Cubs at New York Mets
  { date: "2024-05-18", leagueGroup: "mlb", eventId: "401569157", videoId: "8qyLGEeOtok" }, // New York Mets at Miami Marlins
  { date: "2024-05-21", leagueGroup: "mlb", eventId: "401569203", videoId: "WesQ2NgDBnQ" }, // San Francisco Giants at Pittsburgh Pirates
  { date: "2024-05-21", leagueGroup: "mlb", eventId: "401569190", videoId: "FBLr3GRf5DE" }, // Los Angeles Angels at Houston Astros
  { date: "2024-05-23", leagueGroup: "mlb", eventId: "401569222", videoId: "v2UPN_ahP20" }, // Colorado Rockies at Oakland Athletics
  { date: "2024-05-30", leagueGroup: "mlb", eventId: "401569320", videoId: "oYpt6fP8XXA" }, // Oakland Athletics at Tampa Bay Rays
  { date: "2024-06-07", leagueGroup: "mlb", eventId: "401569426", videoId: "o4FgorFtlNY" }, // Seattle Mariners at Kansas City Royals
  { date: "2024-06-14", leagueGroup: "mlb", eventId: "401569515", videoId: "YIGFqJXBJaI" }, // Oakland Athletics at Minnesota Twins
  { date: "2024-06-18", leagueGroup: "mlb", eventId: "401569574", videoId: "TCI_4uHDhqI" }, // St. Louis Cardinals at Miami Marlins
  { date: "2024-07-01", leagueGroup: "mlb", eventId: "401569739", videoId: "kCl2jJRHjzU" }, // Milwaukee Brewers at Colorado Rockies
  { date: "2024-07-12", leagueGroup: "mlb", eventId: "401569891", videoId: "cAP05nMcFY4" }, // Seattle Mariners at Los Angeles Angels
  { date: "2024-07-13", leagueGroup: "mlb", eventId: "401569900", videoId: "epw3tqVO2Dc" }, // Los Angeles Dodgers at Detroit Tigers
  { date: "2024-07-20", leagueGroup: "mlb", eventId: "401569942", videoId: "b4h9tGLduYo" }, // Boston Red Sox at Los Angeles Dodgers
  { date: "2024-07-22", leagueGroup: "mlb", eventId: "401569971", videoId: "SX93y_L5D9k" }, // Boston Red Sox at Colorado Rockies
  { date: "2024-07-29", leagueGroup: "mlb", eventId: "401570076", videoId: "7LnBbaCkgiY" }, // Washington Nationals at Arizona Diamondbacks
  { date: "2024-07-30", leagueGroup: "mlb", eventId: "401570082", videoId: "mZCzQB5T1CM" }, // Los Angeles Dodgers at San Diego Padres
  { date: "2024-08-11", leagueGroup: "mlb", eventId: "401570235", videoId: "l9H9ZxtUDuo" }, // Atlanta Braves at Colorado Rockies
  { date: "2024-08-12", leagueGroup: "mlb", eventId: "401570248", videoId: "nwIMpHODfSA" }, // Chicago Cubs at Cleveland Guardians
  { date: "2024-08-18", leagueGroup: "mlb", eventId: "401570324", videoId: "huBihyxr8YI" }, // Arizona Diamondbacks at Tampa Bay Rays
  { date: "2024-08-18", leagueGroup: "mlb", eventId: "401570332", videoId: "tPVt-QdvM8k" }, // Minnesota Twins at Texas Rangers
  { date: "2024-08-29", leagueGroup: "mlb", eventId: "401570480", videoId: "k_N4SU-8ND0" }, // Oakland Athletics at Cincinnati Reds
  { date: "2024-09-15", leagueGroup: "mlb", eventId: "401570707", videoId: "gOxheWWqDZ0" }, // Milwaukee Brewers at Arizona Diamondbacks
  { date: "2024-09-22", leagueGroup: "mlb", eventId: "401570797", videoId: "diNFGRRIBCk" }, // Arizona Diamondbacks at Milwaukee Brewers
  { date: "2024-10-06", leagueGroup: "mlb", eventId: "401701018", videoId: "XQgxPKNmA6Y" }, // New York Mets at Philadelphia Phillies (NLDS Game 2)
];

export async function applySeedHighlights(): Promise<void> {
  const byDate = new Map<string, SeedEntry[]>();
  for (const entry of SEED_ENTRIES) {
    const key = `${entry.date}|${entry.leagueGroup}`;
    byDate.set(key, [...(byDate.get(key) ?? []), entry]);
  }

  for (const [key, entries] of byDate) {
    const [date, leagueGroup] = key.split("|") as [string, SeedLeagueGroup];
    try {
      // Ensures a real, fully-formed row exists for each event (via the
      // exact same path every normal request uses - never hand-built),
      // then layers the confirmed video ID on top. MLB dispatches to its own
      // fetcher (mlbGamesService.ts) the same way gamesService.ts's own
      // sport-dispatch elsewhere does - not a BasketballLeagueGroup value.
      // Skip the schedule fetch (one ESPN round-trip per date, plus a
      // processEvent pass per game) when every seed row for this date is
      // already in the store - a finished game that graduated into gameStore
      // long ago just needs the yt_video_id layered on. This keeps a large
      // historical backfill from re-fetching dozens of old slates on boot.
      if (entries.some((e) => !getGame(e.eventId))) {
        if (leagueGroup === "mlb") {
          await getMlbGamesForDate(date);
        } else {
          await getGamesForDate(date, leagueGroup);
        }
      }
      for (const entry of entries) setHighlightsFromSeed(entry.eventId, entry.videoId);
    } catch (err) {
      console.error(`applySeedHighlights: failed for ${key}`, err);
    }
  }
}
