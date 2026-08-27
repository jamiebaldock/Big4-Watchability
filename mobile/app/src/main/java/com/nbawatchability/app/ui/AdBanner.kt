package com.nbawatchability.app.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.MobileAds
import com.nbawatchability.app.ui.theme.SurfaceCardElevated

// Google's published TEST banner ad unit ID - always serves sample ads
// regardless of account, safe to ship in a debug build. Swap for the app's
// real AdMob banner unit ID once James has registered the app in an AdMob
// account (see BACKLOG.md's Monetization section) - using the test ID against
// a live AdMob account risks the account getting flagged for invalid traffic.
private const val TEST_BANNER_AD_UNIT_ID = "ca-app-pub-3940256099942544/6300978111"

/**
 * Anchored banner ad, pinned above [ScrollableBottomNavBar] inside the same
 * Scaffold bottomBar slot (AppRoot.kt) rather than inline in scrolling
 * content - a fixed placement every tab shares, so it doesn't shift as list
 * content scrolls underneath it. Suppressed entirely (not composed) once the
 * "Remove Ads" purchase flag is set, once that lands - no such flag exists
 * yet, so it always renders for now.
 */
@Composable
fun AdBanner(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    // Idempotent - the SDK no-ops a repeat call, so initializing here (rather
    // than a dedicated Application class, which this app doesn't have) is
    // fine even though AdBanner can recompose into existence more than once.
    remember(context) { MobileAds.initialize(context) }

    Surface(color = SurfaceCardElevated) {
        AndroidView(
            modifier = modifier.fillMaxWidth(),
            factory = { ctx ->
                AdView(ctx).apply {
                    setAdSize(AdSize.BANNER)
                    adUnitId = TEST_BANNER_AD_UNIT_ID
                    loadAd(AdRequest.Builder().build())
                }
            }
        )
    }
}
