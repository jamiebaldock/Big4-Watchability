package com.nbawatchability.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nbawatchability.app.data.BACKEND_BASE_URL
import com.nbawatchability.app.data.LeagueGroup
import com.nbawatchability.app.data.NetworkLeagueContentRepository
import com.nbawatchability.app.data.StatsResponse
import kotlinx.coroutines.launch

sealed interface StatsUiState {
    data object Loading : StatsUiState
    data class Error(val message: String) : StatsUiState
    data class Loaded(val data: StatsResponse) : StatsUiState
}

class StatsViewModel : ViewModel() {

    var uiState by mutableStateOf<StatsUiState>(StatsUiState.Loading)
        private set

    private var currentLeagueGroup: LeagueGroup = LeagueGroup.NBA

    fun load(leagueGroup: LeagueGroup) {
        currentLeagueGroup = leagueGroup
        uiState = StatsUiState.Loading
        viewModelScope.launch {
            val result = try {
                StatsUiState.Loaded(NetworkLeagueContentRepository.stats(BACKEND_BASE_URL, leagueGroup))
            } catch (e: Exception) {
                StatsUiState.Error(e.message ?: "Couldn't reach the backend")
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
