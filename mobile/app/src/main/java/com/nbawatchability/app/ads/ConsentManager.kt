package com.nbawatchability.app.ads

import android.app.Activity
import android.content.Context
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform

/**
 * GDPR/UK consent flow (Google's User Messaging Platform), required by
 * AdMob's own policy before requesting ads for a real (non-test) ad unit -
 * skipping this risks the AdMob account getting flagged for policy
 * violations, not just a UX nicety. AdBanner.kt gates MobileAds.initialize
 * and the actual ad load on [requestConsent]'s callback rather than firing
 * both immediately, matching Google's own UMP+AdMob integration guidance.
 *
 * requestConsentInfoUpdate itself is a no-op after the first successful
 * call per process (the SDK caches consent status locally), so calling this
 * again each time AdBanner recomposes into existence is cheap and safe.
 */
object ConsentManager {
    fun requestConsent(activity: Activity, onComplete: (canRequestAds: Boolean) -> Unit) {
        val consentInformation = UserMessagingPlatform.getConsentInformation(activity)
        val params = ConsentRequestParameters.Builder().build()

        consentInformation.requestConsentInfoUpdate(
            activity,
            params,
            {
                UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) {
                    // Ignore the FormError here - canRequestAds() already reflects
                    // whatever the true resulting state is (including "not required
                    // in this region", which counts as ok-to-request).
                    onComplete(consentInformation.canRequestAds())
                }
            },
            {
                // Info update itself failed (e.g. no network this launch) - fall
                // back to whatever canRequestAds() already knows from a prior
                // successful run rather than blocking the banner forever.
                onComplete(consentInformation.canRequestAds())
            }
        )
    }

    /** Gates whether Settings/About should show a "Privacy options" entry point at all. */
    fun isPrivacyOptionsRequired(context: Context): Boolean =
        UserMessagingPlatform.getConsentInformation(context).privacyOptionsRequirementStatus ==
            ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED

    /** Lets a user revisit/change their consent choice later - required by Google's UMP policy once a form has been shown. */
    fun showPrivacyOptionsForm(activity: Activity, onDismissed: () -> Unit = {}) {
        UserMessagingPlatform.showPrivacyOptionsForm(activity) { onDismissed() }
    }
}
