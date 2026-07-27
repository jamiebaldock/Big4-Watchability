package com.nbawatchability.app.ui

import androidx.compose.animation.core.EaseInOutSine
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import com.nbawatchability.app.ui.theme.TextMuted
import com.nbawatchability.app.ui.theme.TierWorthYourTime

// Same handful of good-natured lines the rest of the app's empty/loading
// copy already leans on (FavoritesScreen's empty states, SecretScreen's
// "you found it") - one is picked once per composition (not re-rolled on
// every recomposition, which would flicker distractingly during a real
// multi-second load) so the wait reads as "the app is doing something
// specific for you" rather than a generic spinner.
private val LOADING_LINES = listOf(
    "Finding the good games...",
    "Scouting today's slate...",
    "Checking the watchability...",
    "Ruling out the blowouts...",
    "Lining up the tip-offs..."
)

/**
 * Replaces the old plain CircularProgressIndicator (backlog #F3 - James's
 * ask: a loading spinner reads as a stall, not an intentional wait) with
 * three dots bouncing in a staggered wave, teal (TierWorthYourTime, the
 * app's own "positive/active" accent already used throughout for buttons
 * and highlights) so it reads as on-brand rather than a generic system
 * widget. Shared by both call sites the old LoadingScreen() had - AppRoot's
 * own settings-load gate and GamesTab's per-league ScheduleUiState.Loading
 * - so both the app-launch wait and the "opening a league" wait this
 * session's P1 work was busy shortening both get the same treatment.
 */
@Composable
fun LoadingIndicator(modifier: Modifier = Modifier) {
    val message = remember { LOADING_LINES.random() }
    Column(
        modifier = modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        BouncingDots()
        Spacer(modifier = Modifier.height(16.dp))
        Text(text = message, color = TextMuted, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun BouncingDots() {
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        repeat(3) { index ->
            val bounce by rememberDotBounce(index)
            Box(
                modifier = Modifier
                    .size(12.dp)
                    .graphicsLayer { translationY = -bounce }
                    .clip(CircleShape)
                    .background(TierWorthYourTime)
            )
        }
    }
}

// 450ms rise + 450ms fall per dot (900ms full cycle), staggered 150ms apart
// so the three dots form a visible left-to-right wave rather than moving in
// unison - fast enough to read as lively, slow enough that each dot's own
// rise-and-fall is still clearly visible rather than a blur.
@Composable
private fun rememberDotBounce(index: Int) = rememberInfiniteTransition(label = "dotBounce$index").animateFloat(
    initialValue = 0f,
    targetValue = 14f,
    animationSpec = infiniteRepeatable(
        animation = tween(durationMillis = 450, delayMillis = index * 150, easing = EaseInOutSine),
        repeatMode = RepeatMode.Reverse
    ),
    label = "dotBounce$index"
)
