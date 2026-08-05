package com.nbawatchability.baselineprofile

import androidx.benchmark.macro.junit4.BaselineProfileRule
import androidx.test.filters.LargeTest
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.junit.Rule
import org.junit.Test

private const val PACKAGE_NAME = "com.nbawatchability.app"
private const val TIMEOUT_MS = 15_000L

/**
 * Generates app/src/main/baseline-prof.txt by driving the exact repro from
 * the Favorites->Schedule league-flash investigation (see memory
 * project_favorites_schedule_flash_investigation_2): switch league on
 * Favorites, then jump to Schedule - for every league, not just one, since
 * the root cause is ART interpreting each league's own code paths (NFL-typed
 * rubric weights, WNBA-specific branches, etc.) cold the first time they run
 * in the process. Recording this journey lets ART pre-compile those paths at
 * install time instead of interpreting them live in front of the user.
 */
@LargeTest
class BaselineProfileGenerator {
    @get:Rule
    val baselineProfileRule = BaselineProfileRule()

    @Test
    fun generate() = baselineProfileRule.collect(packageName = PACKAGE_NAME) {
        pressHome()
        startActivityAndWait()

        // Initial cold launch defaults to NBA and shows "Finding the good
        // games..." until the first fetch lands - wait for real content
        // (the bottom nav) before driving any taps.
        device.wait(Until.hasObject(By.text("Favorites")), TIMEOUT_MS)

        device.findObject(By.text("Favorites"))?.click()
        device.wait(Until.hasObject(By.desc("Select league")), TIMEOUT_MS)

        // NBA is already warm from the cold launch above - exercise every
        // OTHER league's Schedule-tab render path once each.
        for (league in listOf("WNBA", "MLB", "NFL", "NHL")) {
            device.findObject(By.desc("Select league"))?.click()
            device.wait(Until.hasObject(By.text(league)), TIMEOUT_MS)
            device.findObject(By.text(league))?.click()

            // Immediately jump to Schedule, same as the real repro - this is
            // the exact moment the new league's GameCard/DayTabsScreen code
            // paths run for the first time in the process.
            device.findObject(By.text("Schedule"))?.click()
            device.wait(Until.hasObject(By.text("Favorites")), TIMEOUT_MS)
            Thread.sleep(2_000)

            device.findObject(By.text("Favorites"))?.click()
            device.wait(Until.hasObject(By.desc("Select league")), TIMEOUT_MS)
        }
    }
}
