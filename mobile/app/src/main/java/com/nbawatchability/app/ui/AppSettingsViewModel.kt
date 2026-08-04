package com.nbawatchability.app.ui

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.nbawatchability.app.data.AppSettings
import com.nbawatchability.app.data.AppSettingsRepository
import com.nbawatchability.app.data.LeagueGroup
import kotlinx.coroutines.launch

class AppSettingsViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = AppSettingsRepository(application.applicationContext)

    var settings by mutableStateOf(AppSettings())
        private set

    // Starts false because [settings] is a hardcoded default (NBA, numeric
    // score off) until DataStore's first emission arrives asynchronously -
    // callers must wait for this before reading [settings], otherwise a
    // persisted league/numeric-score choice loses a race against a request
    // already fired for the wrong (default) league on cold start.
    var isLoaded by mutableStateOf(false)
        private set

    init {
        viewModelScope.launch {
            repository.settings.collect {
                settings = it
                isLoaded = true
            }
        }
    }

    // Updates [settings] in memory immediately, not just via the DataStore
    // round-trip - repository.setSelectedLeague's write is async disk I/O,
    // and the ONLY other place [settings] gets updated is the init block's
    // collect above, which doesn't see that write until DataStore re-emits
    // (a real, measurable gap, not instant). Without this optimistic update,
    // switching league on one tab and immediately navigating to another
    // (e.g. Favorites' dropdown -> tapping into Games) could read the OLD
    // selectedLeague for that first frame - confirmed live as the reported
    // bug (Favorites: switch league A->B, tap Schedule, League A's games
    // flash before jumping to B). The eventual DataStore-driven re-emission
    // still lands afterward, but by then it's just re-confirming the same
    // value already set here, so it's a no-op rather than a second flip.
    fun setSelectedLeague(league: LeagueGroup) {
        settings = settings.copy(selectedLeague = league)
        viewModelScope.launch { repository.setSelectedLeague(league) }
    }

    fun toggleShowNumericScore() {
        viewModelScope.launch { repository.setShowNumericScore(!settings.showNumericScore) }
    }

    fun toggleBumpFavoriteTeamGames() {
        viewModelScope.launch { repository.setBumpFavoriteTeamGames(!settings.bumpFavoriteTeamGames) }
    }

    fun setDefaultLandingTab(tabName: String) {
        viewModelScope.launch { repository.setDefaultLandingTab(tabName) }
    }

    fun toggleHistoryShowScoresByDefault() {
        viewModelScope.launch { repository.setHistoryShowScoresByDefault(!settings.historyShowScoresByDefault) }
    }

    fun toggleMinTierFilterEnabled() {
        viewModelScope.launch { repository.setMinTierFilterEnabled(!settings.minTierFilterEnabled) }
    }

    fun setMinTierFilter(tierName: String) {
        viewModelScope.launch { repository.setMinTierFilter(tierName) }
    }

    fun toggleWifiOnlyHighlights() {
        viewModelScope.launch { repository.setWifiOnlyHighlights(!settings.wifiOnlyHighlights) }
    }

    fun toggleLightTheme() {
        viewModelScope.launch { repository.setLightTheme(!settings.lightTheme) }
    }

    fun setDefaultGameDetailTab(tabName: String) {
        viewModelScope.launch { repository.setDefaultGameDetailTab(tabName) }
    }

    // Same optimistic-update reasoning as setSelectedLeague above - selectLeague
    // calls this right before setSelectedLeague, so without this, the same
    // DataStore round-trip gap would apply here too (a stale isAllLeaguesSelected
    // read feeding GamesTab's leagueGroups computation alongside the stale league).
    fun setAllLeaguesSelected(value: Boolean) {
        settings = settings.copy(isAllLeaguesSelected = value)
        viewModelScope.launch { repository.setAllLeaguesSelected(value) }
    }

    fun togglePlayerHaterMode() {
        viewModelScope.launch { repository.setPlayerHaterMode(!settings.playerHaterMode) }
    }

    fun toggleConfettiEnabled() {
        viewModelScope.launch { repository.setConfettiEnabled(!settings.confettiEnabled) }
    }

    /**
     * Picks a single real league, turning "All Leagues" back off - the one
     * place this reset happens, shared by every tab's dropdown
     * (TitleLeagueSelector's per-league menu items all call this same
     * callback), rather than each tab re-implementing "unset All Leagues
     * when a specific league is picked" on its own.
     *
     * Persists both fields as ONE DataStore transaction
     * (setSelectedLeagueAndUnsetAllLeagues), not two separate calls to
     * setSelectedLeague/setAllLeaguesSelected - see that repository method's
     * own doc comment for why calling them separately let an intermediate,
     * half-updated DataStore emission clobber this function's optimistic
     * settings update back to the OLD league for a frame (the reported
     * Favorites-switch-then-tap-Schedule flash).
     */
    fun selectLeague(league: LeagueGroup) {
        settings = settings.copy(selectedLeague = league, isAllLeaguesSelected = false)
        viewModelScope.launch { repository.setSelectedLeagueAndUnsetAllLeagues(league) }
    }

    /**
     * Flips [league] in the dropdown's visible set. Two safety rules the
     * Settings toggle UI can't enforce on its own: never let the set go
     * fully empty (would leave the dropdown with nothing to pick), and if
     * the league being turned off is the one currently selected, fall back
     * to NBA (or whatever else remains enabled, if NBA itself was somehow
     * turned off) rather than leaving selectedLeague pointing at a league
     * that no longer shows in its own dropdown.
     */
    fun toggleLeagueEnabled(league: LeagueGroup) {
        val current = settings.enabledLeagues
        val updated = if (league in current) current - league else current + league
        if (updated.isEmpty()) return

        viewModelScope.launch { repository.setEnabledLeagues(updated) }
        if (settings.selectedLeague !in updated) {
            // Routed through the class's own setSelectedLeague (not
            // repository.setSelectedLeague directly) so this fallback picks up
            // the same optimistic in-memory update as every other league
            // switch - same DataStore-round-trip gap would otherwise apply here.
            setSelectedLeague(updated.find { it == LeagueGroup.NBA } ?: updated.first())
        }
    }
}
