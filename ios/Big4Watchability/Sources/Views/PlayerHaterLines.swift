import Foundation

// Swift mirror of GameCard.kt's player-hater roast banks - spoiler-free
// versions only (no stat numbers), just gentle mockery that the player
// showed up. Picked once per performer by the caller (keyed on name+line),
// not re-rolled on every redraw, so it doesn't visibly flicker as a tile
// scrolls in and out of view.
private let playerHaterSingleStatLinesSpoilerFree = [
    "%@ finally decided to play tonight - color me shocked.",
    "%@: putting in actual effort. Groundbreaking.",
    "Wow, %@ showed up. Somebody alert the scoreboard.",
    "%@ actually remembered they're on the team.",
    "Give %@ a hand for participating. Truly inspiring.",
    "%@ had a game tonight - no further comment needed.",
    "Oh wow, %@ decided to exist. Revolutionary.",
    "%@ pulled off the impossible: being present.",
    "Credit to %@ for at least trying tonight.",
    "%@: 'I'm gonna show up.' And then they did. Riveting stuff.",
    "Respect to %@ for a genuine effort. Maybe.",
    "Big night for %@ - and I mean that generously.",
    "Oh wow, %@ actually contributed something. Let's celebrate.",
    "%@ stepped up - the bar was definitely on the floor.",
    "Give it up for %@ just... existing out there tonight.",
    "%@ played a real game tonight.",
    "Oh wow, %@ remembered the rules. How refreshing.",
    "%@: 'I can be useful.' Today was the day they tested that theory.",
    "Applause for %@, whose effort tonight was... present.",
    "Oh wow, %@ didn't phone this one in. Shocking twist."
]

private let playerHaterMultiStatSpoilerFree = [
    "%@ finally got it together. Only took long enough.",
    "%@ showed up with their whole game tonight. Plot twist.",
    "Oh wow, %@ was actually useful. In multiple ways. Historic.",
    "%@: 'I can contribute across the board.' And tonight they proved it, kinda.",
    "Oh wow, %@ did multiple things well. Stop the presses.",
    "%@ had one of those games where they remembered how to play."
]

// [line] is always "NUMBER label" pairs, comma-separated - a single stat for
// every sport except an NBA/WNBA triple-double, which is always exactly
// "X PTS, Y REB, Z AST".
private func statPartCount(_ line: String) -> Int {
    line.components(separatedBy: ", ").filter { part in
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        guard let firstSpace = trimmed.firstIndex(of: " ") else { return false }
        return Int(trimmed[trimmed.startIndex..<firstSpace]) != nil
    }.count
}

/// Spoiler-free roast: no stat numbers mentioned, just gentle mockery that
/// the player showed up.
func playerHaterLine(name: String, line: String) -> String {
    let bank = statPartCount(line) < 2 ? playerHaterSingleStatLinesSpoilerFree : playerHaterMultiStatSpoilerFree
    let template = bank.randomElement() ?? "%@ played tonight."
    return String(format: template, name)
}
