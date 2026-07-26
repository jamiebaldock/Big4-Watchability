package com.nbawatchability.app.ui

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.nbawatchability.app.data.AdminAuthRepository
import com.nbawatchability.app.data.AdminMissingGame
import com.nbawatchability.app.data.AdminNetworkRepository
import com.nbawatchability.app.data.AdminStats
import com.nbawatchability.app.data.AdminUnauthorizedException
import com.nbawatchability.app.data.AlertsRepository
import com.nbawatchability.app.data.BACKEND_BASE_URL
import kotlinx.coroutines.launch

sealed interface AdminDashboardState {
    data object Loading : AdminDashboardState
    data class Error(val message: String) : AdminDashboardState
    data class Loaded(val stats: AdminStats, val missingGames: List<AdminMissingGame>) : AdminDashboardState
}

/** Per-game outcome of a manual "Re-search" tap, keyed by eventId - lets the row show its own inline result without a full dashboard reload. */
sealed interface ResendState {
    data object InFlight : ResendState
    data class Found(val title: String) : ResendState
    data object NotFound : ResendState
    data class Failed(val message: String) : ResendState
}

/** Outcome of the "Send test push" button - a single shared state (not keyed like ResendState) since there's only ever one test push in flight at a time. */
sealed interface TestPushState {
    data object InFlight : TestPushState
    data class Sent(val away: String, val home: String) : TestPushState
    data class Failed(val message: String) : TestPushState
}

class AdminViewModel(application: Application) : AndroidViewModel(application) {

    private val authRepository = AdminAuthRepository(application.applicationContext)
    // Same on-device identity Alerts registration itself uses (AlertsRepository/
    // AlertsFirebaseMessagingService) - the test-push button targets THIS
    // device's own registered token, so it has to ask under the same identity
    // that registration used, not generate a fresh one.
    private val alertsRepository = AlertsRepository(application.applicationContext)

    // Null until the persisted token flow's first emission arrives - callers
    // (AppRoot) should treat null as "still figuring out whether a session
    // already exists," not the same as "definitely logged out," the same
    // isLoaded pattern AppSettingsViewModel already uses for its own
    // DataStore-backed state.
    var token: String? by mutableStateOf(null)
        private set
    var isTokenLoaded by mutableStateOf(false)
        private set

    var loginError: String? by mutableStateOf(null)
        private set
    var isLoggingIn by mutableStateOf(false)
        private set

    var dashboardState: AdminDashboardState by mutableStateOf(AdminDashboardState.Loading)
        private set

    // A Compose-observable map (not a plain mutableMapOf) - resendStateFor
    // reads individual entries from this during composition, and only a
    // snapshot-backed map notifies Compose when one of those entries
    // changes underneath it.
    private val resendStates = mutableStateMapOf<String, ResendState>()

    var testPushState: TestPushState? by mutableStateOf(null)
        private set

    init {
        viewModelScope.launch {
            authRepository.token.collect {
                token = it
                isTokenLoaded = true
            }
        }
    }

    fun resendStateFor(eventId: String): ResendState? = resendStates[eventId]

    fun submitPin(pin: String) {
        if (isLoggingIn) return
        isLoggingIn = true
        loginError = null
        viewModelScope.launch {
            try {
                val newToken = AdminNetworkRepository.login(BACKEND_BASE_URL, pin)
                authRepository.setToken(newToken)
                // token/isTokenLoaded update via the collect above once
                // DataStore's write lands - loadDashboard reads it fresh
                // itself rather than relying on that race, since it needs
                // the token as an explicit argument anyway.
                loadDashboard(newToken)
            } catch (e: AdminUnauthorizedException) {
                loginError = "Incorrect PIN"
            } catch (e: Exception) {
                loginError = e.message ?: "Couldn't reach the backend"
            } finally {
                isLoggingIn = false
            }
        }
    }

    fun logOut() {
        viewModelScope.launch { authRepository.clearToken() }
    }

    fun loadDashboard(tokenOverride: String? = null) {
        val activeToken = tokenOverride ?: token ?: return
        dashboardState = AdminDashboardState.Loading
        viewModelScope.launch {
            try {
                val stats = AdminNetworkRepository.stats(BACKEND_BASE_URL, activeToken)
                val missing = AdminNetworkRepository.missingHighlights(BACKEND_BASE_URL, activeToken)
                dashboardState = AdminDashboardState.Loaded(stats, missing)
            } catch (e: AdminUnauthorizedException) {
                // The persisted token's server-side session expired (24h TTL,
                // or the backend restarted and lost its in-memory token set)
                // - clear it so AppRoot falls back to the PIN screen instead
                // of showing a dead dashboard.
                authRepository.clearToken()
            } catch (e: Exception) {
                dashboardState = AdminDashboardState.Error(e.message ?: "Couldn't reach the backend")
            }
        }
    }

    fun resendHighlights(eventId: String) {
        val activeToken = token ?: return
        resendStates[eventId] = ResendState.InFlight
        viewModelScope.launch {
            try {
                val result = AdminNetworkRepository.resendHighlights(BACKEND_BASE_URL, activeToken, eventId)
                resendStates[eventId] = if (result.matched) {
                    ResendState.Found(result.title ?: "Match found")
                } else {
                    ResendState.NotFound
                }
                // A real match changes what the missing-games list itself
                // should show (this game no longer belongs on it) and the
                // day's search count just moved - simplest correct thing is
                // to refresh both from the server rather than patch state
                // locally in two places.
                if (result.matched) loadDashboard()
            } catch (e: Exception) {
                resendStates[eventId] = ResendState.Failed(e.message ?: "Search failed")
            }
        }
    }

    /**
     * Sends a real push (via alertsPoller.ts's exact same payload shape) to
     * this device's own registered token, targeting whatever real game the
     * backend picks for today - lets James verify the full tap -> deep-link
     * path (AlertsFirebaseMessagingService -> DeepLinkViewModel -> AppRoot's
     * jumpToDate) on demand, without waiting for a real close-swing game.
     */
    fun sendTestPush() {
        val activeToken = token ?: return
        testPushState = TestPushState.InFlight
        viewModelScope.launch {
            try {
                val deviceId = alertsRepository.getOrCreateDeviceId()
                val result = AdminNetworkRepository.sendTestPush(BACKEND_BASE_URL, activeToken, deviceId)
                testPushState = TestPushState.Sent(result.away ?: "?", result.home ?: "?")
            } catch (e: Exception) {
                testPushState = TestPushState.Failed(e.message ?: "Send failed")
            }
        }
    }
}
