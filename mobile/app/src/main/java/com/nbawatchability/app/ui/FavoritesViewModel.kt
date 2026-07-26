package com.nbawatchability.app.ui

import android.app.Application
import android.widget.Toast
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.nbawatchability.app.data.BACKEND_BASE_URL
import com.nbawatchability.app.data.FavoritePlayer
import com.nbawatchability.app.data.FavoritesRepository
import com.nbawatchability.app.data.LeagueGroup
import com.nbawatchability.app.data.NetworkLeagueContentRepository
import com.nbawatchability.app.data.Team
import kotlinx.coroutines.launch

const val MAX_FAVORITE_TEAMS = 5
const val MAX_FAVORITE_PLAYERS = 10
// Player Hater Mode easter egg - global cap (not per-league like the two
// above), James's specific call: up to 10 hated players total, across every
// league at once.
const val MAX_HATED_PLAYERS = 10

class FavoritesViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = FavoritesRepository(application.applicationContext)

    var favoriteTeams by mutableStateOf<List<Team>>(emptyList())
        private set

    // True once the very first DataStore emission (even an empty list) has
    // arrived - lets the Favorites tab distinguish "still loading" from "genuinely no
    // favorites yet" instead of flashing an empty state first.
    var isLoaded by mutableStateOf(false)
        private set

    var favoritePlayers by mutableStateOf<List<FavoritePlayer>>(emptyList())
        private set

    var hatedPlayers by mutableStateOf<List<FavoritePlayer>>(emptyList())
        private set

    init {
        viewModelScope.launch {
            repository.favoriteTeams.collect {
                favoriteTeams = it
                isLoaded = true
                reconcileMissingTeamIds(it)
            }
        }
        viewModelScope.launch {
            repository.favoritePlayers.collect { favoritePlayers = it }
        }
        viewModelScope.launch {
            repository.hatedPlayers.collect { hatedPlayers = it }
        }
    }

    /**
     * Backfills a real ESPN team id onto any favorite that doesn't have one -
     * silently a no-op once every favorite already has an id (the common
     * case), so this is cheap to call on every emission. A blank id only
     * ever happens via the long-press-a-team-name-on-a-tile quick-add
     * (GameCard.kt's onLongPress constructs Team(name, logo, leagueGroup)
     * with no id, since GameJson carries no team-id field to give it) - the
     * "Add a favorite team" search screen always uses the real Team object
     * straight from the backend's /teams response, id included. The missing
     * id was invisible on the Teams management page (no id check there) but
     * silently dropped that team from Favorites' Upcoming/Past Games list
     * (FavoriteGamesViewModel.fetchAll requires id.isNotBlank() - the
     * backend's team-schedule endpoint needs a real ESPN id to query)
     * - James's report, 2026-07-27.
     *
     * Fetches each affected league's real /teams list once and matches by
     * name - the same lookup TeamsViewModel already does for the search
     * screen, just run automatically here instead of requiring the user to
     * open that screen for it to happen. Runs for every league with at
     * least one id-less favorite (not just the one most recently added),
     * so this also self-heals any favorite added before this fix existed,
     * not just new ones going forward.
     */
    private fun reconcileMissingTeamIds(current: List<Team>) {
        val leaguesNeedingRepair = current
            .filter { it.id.isBlank() && it.leagueGroup != null }
            .mapNotNull { team -> LeagueGroup.entries.find { it.apiValue == team.leagueGroup } }
            .distinct()
        if (leaguesNeedingRepair.isEmpty()) return

        viewModelScope.launch {
            // Built up locally across every league before persisting once at
            // the end, rather than writing (and re-reading the ViewModel's
            // own favoriteTeams) per league - that write is an async
            // DataStore round-trip, so a second league's repair could
            // otherwise run against a stale pre-first-repair snapshot and
            // clobber it.
            var working = current
            for (leagueGroup in leaguesNeedingRepair) {
                val realTeams = runCatching { NetworkLeagueContentRepository.teams(BACKEND_BASE_URL, leagueGroup).teams }
                    .getOrNull() ?: continue
                val byName = realTeams.associateBy { it.name }
                working = working.map { fav ->
                    if (fav.id.isBlank() && fav.leagueGroup == leagueGroup.apiValue) byName[fav.name] ?: fav else fav
                }
            }
            if (working != current) repository.setFavoriteTeams(working)
        }
    }

    fun isFavoriteTeam(name: String): Boolean = favoriteTeams.any { it.name == name }

    fun isFavoritePlayer(name: String): Boolean = favoritePlayers.any { it.name == name }

    fun isHatedPlayer(name: String): Boolean = hatedPlayers.any { it.name == name }

    /**
     * Adds [team] if not already favorited, removes it otherwise - the same
     * toggle shape used everywhere else in this app (starring, league
     * enabling). A plain Toast (not a Compose overlay) carries the cap-reached
     * message specifically because this is reachable from a long-press on any
     * team logo across several different screens (Games, Starred, History,
     * Leaders) - a Toast needs no per-screen overlay wiring to show up
     * correctly regardless of which one triggered it.
     *
     * The cap is per-league (per James' request), not global - up to
     * MAX_FAVORITE_TEAMS in NBA *and* MAX_FAVORITE_TEAMS in WNBA *and* ...,
     * counted by matching [team]'s own leagueGroup against every other
     * currently-favorited team's, not the total list size.
     */
    fun toggleFavoriteTeam(team: Team) {
        val alreadyFavorited = isFavoriteTeam(team.name)
        if (!alreadyFavorited) {
            val countInSameLeague = favoriteTeams.count { it.leagueGroup == team.leagueGroup }
            if (countInSameLeague >= MAX_FAVORITE_TEAMS) {
                Toast.makeText(getApplication(), "Up to $MAX_FAVORITE_TEAMS favorite teams per league for now", Toast.LENGTH_SHORT).show()
                return
            }
        }
        val updated = if (alreadyFavorited) favoriteTeams.filterNot { it.name == team.name } else favoriteTeams + team
        viewModelScope.launch { repository.setFavoriteTeams(updated) }
    }

    /**
     * Same per-league cap shape as toggleFavoriteTeam above (James' request
     * to match the teams cap change) - up to MAX_FAVORITE_PLAYERS in NBA
     * *and* MAX_FAVORITE_PLAYERS in WNBA *and* ..., counted by matching
     * [player]'s own leagueGroup against every other currently-favorited
     * player's, not the total list size.
     */
    fun toggleFavoritePlayer(player: FavoritePlayer) {
        val alreadyFavorited = isFavoritePlayer(player.name)
        if (!alreadyFavorited) {
            val countInSameLeague = favoritePlayers.count { it.leagueGroup == player.leagueGroup }
            if (countInSameLeague >= MAX_FAVORITE_PLAYERS) {
                Toast.makeText(getApplication(), "Up to $MAX_FAVORITE_PLAYERS favorite players per league for now", Toast.LENGTH_SHORT).show()
                return
            }
        }
        val updated = if (alreadyFavorited) favoritePlayers.filterNot { it.name == player.name } else favoritePlayers + player
        viewModelScope.launch { repository.setFavoritePlayers(updated) }
    }

    /**
     * Player Hater Mode easter egg - independent of toggleFavoritePlayer
     * above (a player can be hated without being favorited, or favorited
     * without being hated). Cap is global (MAX_HATED_PLAYERS), not per-league
     * - unlike favorites, there's no per-league reasoning to preserve here.
     */
    fun toggleHatedPlayer(player: FavoritePlayer) {
        val alreadyHated = isHatedPlayer(player.name)
        if (!alreadyHated && hatedPlayers.size >= MAX_HATED_PLAYERS) {
            Toast.makeText(getApplication(), "Up to $MAX_HATED_PLAYERS players you're not a fan of for now", Toast.LENGTH_SHORT).show()
            return
        }
        val updated = if (alreadyHated) hatedPlayers.filterNot { it.name == player.name } else hatedPlayers + player
        viewModelScope.launch { repository.setHatedPlayers(updated) }
    }
}
