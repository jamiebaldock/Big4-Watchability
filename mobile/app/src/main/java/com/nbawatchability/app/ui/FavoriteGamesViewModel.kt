package com.nbawatchability.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nbawatchability.app.data.BACKEND_BASE_URL
import com.nbawatchability.app.data.Game
import com.nbawatchability.app.data.LeagueGroup
import com.nbawatchability.app.data.NetworkGameRepository
import com.nbawatchability.app.data.Team
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import java.time.OffsetDateTime

sealed interface FavoriteGamesUiState {
    data object Loading : FavoriteGamesUiState
    data class Error(val message: String) : FavoriteGamesUiState
    data class Loaded(val games: List<Game>) : FavoriteGamesUiState
}

/**
 * Aggregates "every game involving any of my favorited teams" across every
 * league at once - the Favorites tab's Games page, distinct from
 * GameListViewModel (scoped to one league's day-by-day live slate). One
 * /team-schedule call per favorited team (each returns that team's whole
 * current-season schedule, past and upcoming, no client-side date
 * windowing - James's call), merged into one flat list spanning however
 * many leagues the user has favorited teams in.
 *
 * A team without a real ESPN id or leagueGroup (favorited before either
 * field existed) is silently skipped rather than erroring the whole page -
 * there's no schedule to fetch for it, same "can't do anything useful with
 * this old data, don't crash over it" reasoning as every other leagueGroup/
 * id-null fallback already in this codebase.
 */
class FavoriteGamesViewModel : ViewModel() {

    var uiState by mutableStateOf<FavoriteGamesUiState>(FavoriteGamesUiState.Loading)
        private set

    // AppRoot fires load() from two separate LaunchedEffects (initial
    // composition, and again on every favoriteTeams change) - without a
    // generation guard, an older call's slower multi-team fetch landing
    // after a newer call's faster one would silently overwrite the correct,
    // up-to-date result with a stale one. Same shape/reasoning as
    // GameListViewModel's loadToken.
    private var loadToken = 0

    fun load(favoriteTeams: List<Team>) {
        val token = ++loadToken
        uiState = FavoriteGamesUiState.Loading
        viewModelScope.launch {
            val result = try {
                FavoriteGamesUiState.Loaded(fetchAll(favoriteTeams))
            } catch (e: Exception) {
                FavoriteGamesUiState.Error(e.message ?: "Couldn't reach the backend")
            }
            if (token == loadToken) uiState = result
        }
    }

    fun retry(favoriteTeams: List<Team>) = load(favoriteTeams)

    // Each team's fetch is independent - one team's failure (or having no
    // usable id/leagueGroup) doesn't sink every other team's already-fetched
    // games. Only surfaces as a page-level Error if literally every fetch
    // that was attempted failed; a partial result (some teams succeeded,
    // some didn't) is still shown rather than discarded.
    private suspend fun fetchAll(favoriteTeams: List<Team>): List<Game> = coroutineScope {
        val eligible = favoriteTeams.filter { it.id.isNotBlank() && it.leagueGroup != null }
        val results = eligible.map { team ->
            async {
                val leagueGroup = LeagueGroup.entries.find { it.apiValue == team.leagueGroup }
                if (leagueGroup == null) {
                    Result.success(emptyList())
                } else {
                    runCatching { NetworkGameRepository.teamSchedule(BACKEND_BASE_URL, team.id, leagueGroup) }
                }
            }
        }.awaitAll()

        if (results.isNotEmpty() && results.none { it.isSuccess }) {
            throw results.first().exceptionOrNull() ?: Exception("Couldn't reach the backend")
        }

        results.flatMap { it.getOrDefault(emptyList()) }
            .distinctBy { it.id ?: "${it.tipoffUtc}-${it.away}-${it.home}" }
            .sortedBy { OffsetDateTime.parse(it.tipoffUtc) }
    }
}
