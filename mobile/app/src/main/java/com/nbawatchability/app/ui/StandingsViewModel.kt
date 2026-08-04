package com.nbawatchability.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nbawatchability.app.data.BACKEND_BASE_URL
import com.nbawatchability.app.data.LeagueGroup
import com.nbawatchability.app.data.NetworkLeagueContentRepository
import com.nbawatchability.app.data.StandingsResponse
import kotlinx.coroutines.launch

sealed interface StandingsUiState {
    data object Loading : StandingsUiState
    data class Error(val message: String) : StandingsUiState
    data class Loaded(val data: StandingsResponse) : StandingsUiState
}

class StandingsViewModel : ViewModel() {

    var uiState by mutableStateOf<StandingsUiState>(StandingsUiState.Loading)
        private set

    private var currentLeagueGroup: LeagueGroup = LeagueGroup.NBA

    fun load(leagueGroup: LeagueGroup) {
        currentLeagueGroup = leagueGroup
        uiState = StandingsUiState.Loading
        viewModelScope.launch {
            val result = try {
                StandingsUiState.Loaded(NetworkLeagueContentRepository.standings(BACKEND_BASE_URL, leagueGroup))
            } catch (e: Exception) {
                StandingsUiState.Error(e.message ?: "Couldn't reach the backend")
            }
            // Same stale-response guard as RosterViewModel/LeagueRostersViewModel -
            // discard a result for a league the caller has since switched away
            // from, so a slow-to-resolve earlier league can't overwrite a
            // faster-resolving later one (the same shape as James's 2026-07-24
            // "WNBA search showing NBA data" report).
            if (currentLeagueGroup == leagueGroup) {
                uiState = result
            }
        }
    }

    fun retry() = load(currentLeagueGroup)
}
