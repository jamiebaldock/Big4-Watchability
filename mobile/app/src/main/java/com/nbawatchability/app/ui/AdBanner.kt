package com.nbawatchability.app.ui

import android.app.Activity
import android.util.Log
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.MobileAds
import com.nbawatchability.app.ads.ConsentManager
import com.nbawatchability.app.ui.theme.SurfaceCardElevated

// Real banner ad unit ID for the app's own AdMob account (registered
// 2026-09-16). See BACKLOG.md's Monetization section.
private const val BANNER_AD_UNIT_ID = "ca-app-pub-6295039345620062/5400756591"

// AdSize.BANNER is 320x50 - reserve its height unconditionally so the row keeps
// a stable size whether or not an ad has filled yet. Without this the AdView
// reports 0 height until its first fill, which (under a wrap-content parent)
// collapses the banner entirely and shifts layout when it finally loads.
private val BANNER_HEIGHT = 50.dp

/**
 * Anchored banner ad, pinned above [ScrollableBottomNavBar] inside the same
 * Scaffold bottomBar slot (AppRoot.kt) rather than inline in scrolling
 * content - a fixed placement every tab shares, so it doesn't shift as list
 * content scrolls underneath it. Suppressed entirely (not composed) once the
 * "Remove Ads" purchase flag is set, once that lands - no such flag exists
 * yet, so it always renders for now.
 *
 * The actual AdView isn't built until ConsentManager resolves whether ads
 * can be requested (GDPR/UK consent flow) - AdMob policy requires the
 * consent check to happen before MobileAds.initialize/loadAd, not just
 * before rendering. Until then this reserves the same height as an empty
 * strip, so nothing shifts once the real ad slots in.
 */
@Composable
fun AdBanner(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var canRequestAds by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        val activity = context as? Activity
        if (activity == null) {
            // Shouldn't happen in practice (this composable only ever renders
            // inside MainActivity's setContent), but fail open rather than
            // permanently blank if it ever does.
            canRequestAds = true
            return@LaunchedEffect
        }
        ConsentManager.requestConsent(activity) { result -> canRequestAds = result }
    }

    Surface(color = SurfaceCardElevated) {
        Box(modifier = modifier.fillMaxWidth().height(BANNER_HEIGHT)) {
            if (canRequestAds) {
                // Idempotent - the SDK no-ops a repeat call, so initializing here
                // (rather than a dedicated Application class, which this app
                // doesn't have) is fine even though AdBanner can recompose into
                // existence more than once. Deliberately only reached once
                // consent is resolved, matching Google's own UMP+AdMob ordering.
                remember(context) { MobileAds.initialize(context) }

                AndroidView(
                    modifier = Modifier.fillMaxWidth().height(BANNER_HEIGHT),
                    factory = { ctx ->
                        AdView(ctx).apply {
                            setAdSize(AdSize.BANNER)
                            adUnitId = BANNER_AD_UNIT_ID
                            adListener = object : AdListener() {
                                override fun onAdLoaded() {
                                    Log.d("AdBanner", "ad loaded")
                                }
                                override fun onAdFailedToLoad(error: LoadAdError) {
                                    Log.w("AdBanner", "ad failed to load: ${error.code} ${error.message}")
                                }
                            }
                            loadAd(AdRequest.Builder().build())
                        }
                    }
                )
            }
        }
    }
}
