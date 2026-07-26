package com.nbawatchability.app

import android.Manifest
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.webkit.WebView
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.nbawatchability.app.alerts.StartingSoonRefreshWorker
import com.nbawatchability.app.ui.AppRoot
import com.nbawatchability.app.ui.AppSettingsViewModel
import com.nbawatchability.app.ui.DeepLinkViewModel
import com.nbawatchability.app.ui.theme.NbaWatchabilityTheme
import com.nbawatchability.app.util.FileLogger

class MainActivity : ComponentActivity() {

    private val requestNotificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* no-op either way - alerts simply stay silent if denied */ }

    // Same Activity-scoped instance AppRoot() also obtains via viewModel() -
    // shared ViewModelStoreOwner is what lets onNewIntent's warm-start tap
    // (below) reach AppRoot without recreating it.
    private val deepLinkViewModel: DeepLinkViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize file logger for performance diagnostics (synced to Drive)
        FileLogger.init(this)

        // Cold start (app wasn't running) via a notification tap - onNewIntent
        // below only fires for a warm start (Activity already exists).
        deepLinkViewModel.consume(intent)

        // Debug builds only (never a release/Play Store build) - lets any
        // WebView in the app, including the highlights player's internal
        // one, be inspected via chrome://inspect over USB.
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            WebView.setWebContentsDebuggingEnabled(true)
        }

        // Android 13+ (API 33) requires this at runtime before any
        // notification, including Alerts pushes, can actually show.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }

        // Starting-soon alarms: make sure the 12-hourly reschedule pass
        // exists (KEEP - never resets an existing cadence) and run one now,
        // so a fresh install/update has alarms without waiting for the
        // first periodic tick.
        StartingSoonRefreshWorker.enqueuePeriodic(this)
        StartingSoonRefreshWorker.enqueueOneShot(this)

        setContent {
            // Same AppSettingsViewModel instance AppRoot() itself later grabs
            // via viewModel() (both scoped to this same Activity) - read here
            // too, specifically so the light-theme choice is known before
            // MaterialTheme picks a color scheme, rather than flashing dark
            // and then repainting once AppRoot's own settings read resolves.
            val appSettingsViewModel: AppSettingsViewModel = viewModel()
            NbaWatchabilityTheme(isLightTheme = appSettingsViewModel.settings.lightTheme) {
                AppRoot()
            }
        }
    }

    // Warm start: app already running (singleTop launchMode, see
    // AndroidManifest.xml) when a notification is tapped - onCreate above
    // only ever fires once per process, so this is the only path a deep
    // link from a second/third notification tap can arrive on.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deepLinkViewModel.consume(intent)
    }
}
