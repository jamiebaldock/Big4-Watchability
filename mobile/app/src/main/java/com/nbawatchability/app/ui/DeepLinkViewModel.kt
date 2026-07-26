package com.nbawatchability.app.ui

import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import com.nbawatchability.app.data.LeagueGroup
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId

/**
 * A tapped Alerts push (AlertsFirebaseMessagingService) -> which game/day to
 * land on. [date] is the game's tipoff re-bucketed into the device's local
 * date (same OffsetDateTime -> local-zone conversion GameListViewModel's own
 * localDateOf already uses), not the raw UTC calendar date, so this lands on
 * the same day-tab the Games tab itself would show this game under.
 */
data class PendingGameDeepLink(val eventId: String, val league: LeagueGroup, val date: LocalDate)

// GameJson's "lg" values (backend/src/types.ts) - "summer" bundles under the
// NBA league group client-side the same way alertsPoller.ts's own
// normalizedLeague already does server-side for alert eligibility.
private fun leagueGroupForPushValue(lg: String?): LeagueGroup? = when (lg) {
    "nba", "summer" -> LeagueGroup.NBA
    "wnba" -> LeagueGroup.WNBA
    "mlb" -> LeagueGroup.MLB
    "nfl" -> LeagueGroup.NFL
    "nhl" -> LeagueGroup.NHL
    else -> null
}

private const val EXTRA_EVENT_ID = "deepLinkEventId"
private const val EXTRA_LEAGUE = "deepLinkLeague"
private const val EXTRA_UTC = "deepLinkUtc"

/**
 * Scoped to MainActivity (obtained via viewModel() both there and in
 * AppRoot, same ViewModelStoreOwner) so a tap that arrives while the app is
 * already running (onNewIntent, not a fresh onCreate) still reaches AppRoot
 * reactively - a plain Activity-scope var wouldn't survive recomposition,
 * and there's no other object both MainActivity and AppRoot already share.
 */
class DeepLinkViewModel : ViewModel() {
    var pending by mutableStateOf<PendingGameDeepLink?>(null)
        private set

    fun consume(intent: Intent?) {
        val eventId = intent?.getStringExtra(EXTRA_EVENT_ID) ?: return
        val league = leagueGroupForPushValue(intent.getStringExtra(EXTRA_LEAGUE)) ?: return
        val utc = intent.getStringExtra(EXTRA_UTC) ?: return
        val date = runCatching {
            OffsetDateTime.parse(utc).atZoneSameInstant(ZoneId.systemDefault()).toLocalDate()
        }.getOrNull() ?: return
        pending = PendingGameDeepLink(eventId, league, date)
        // Consumed intents shouldn't re-fire on a later onNewIntent/rotation
        // replay - clear the extras so a stale intent object can't re-post
        // the same deep link a second time.
        intent.removeExtra(EXTRA_EVENT_ID)
    }

    fun clear() {
        pending = null
    }

    companion object {
        fun putExtras(intent: Intent, eventId: String, league: String, utc: String) {
            intent.putExtra(EXTRA_EVENT_ID, eventId)
            intent.putExtra(EXTRA_LEAGUE, league)
            intent.putExtra(EXTRA_UTC, utc)
        }
    }
}
