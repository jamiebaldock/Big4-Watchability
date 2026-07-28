package com.nbawatchability.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import com.nbawatchability.app.ui.theme.SurfaceCardElevated
import com.nbawatchability.app.ui.theme.TextMuted
import com.nbawatchability.app.ui.theme.TextPrimary
import com.nbawatchability.app.ui.theme.TierInstantClassic
import com.nbawatchability.app.ui.theme.TierWorthYourTime

/**
 * History tile's own "paste a link" popup - reached by tapping
 * AddHighlightLinkRow (GameCard.kt) on a final game with no highlights link
 * yet. Two steps in one dialog rather than two separate screens: an admin
 * PIN gate first if there's no live session (same server-side PIN check as
 * the hidden Admin page, reusing AdminViewModel's own token/login state so a
 * PIN entered here also unlocks Admin proper and vice versa), then the
 * actual link entry once logged in - same submission this dialog's
 * [onSubmitLink] wires to (AdminViewModel.submitManualHighlightFromHistory,
 * which is the exact validation/setHighlightsFromSeed path Admin's own
 * "paste a link myself" fallback already uses).
 */
@Composable
fun AddHighlightLinkDialog(
    isLoggedIn: Boolean,
    isLoggingIn: Boolean,
    loginError: String?,
    onSubmitPin: (String) -> Unit,
    onSubmitLink: (url: String, onSuccess: (String) -> Unit, onError: (String) -> Unit) -> Unit,
    onLinkSaved: (String) -> Unit,
    onDismiss: () -> Unit
) {
    Dialog(onDismissRequest = onDismiss) {
        Surface(color = SurfaceCardElevated, shape = RoundedCornerShape(16.dp)) {
            Column(modifier = Modifier.fillMaxWidth().padding(20.dp)) {
                if (!isLoggedIn) {
                    var pin by remember { mutableStateOf("") }
                    Text(
                        text = "Enter admin PIN",
                        color = TextPrimary,
                        style = MaterialTheme.typography.titleMedium
                    )
                    Text(
                        text = "Same PIN as the hidden Admin page.",
                        color = TextMuted,
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.padding(top = 2.dp)
                    )
                    OutlinedTextField(
                        value = pin,
                        onValueChange = { pin = it.filter(Char::isDigit) },
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { if (pin.isNotEmpty()) onSubmitPin(pin) }),
                        singleLine = true,
                        enabled = !isLoggingIn,
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = TextPrimary,
                            unfocusedTextColor = TextPrimary,
                            focusedBorderColor = TierWorthYourTime,
                            unfocusedBorderColor = TextMuted
                        ),
                        modifier = Modifier.fillMaxWidth().padding(top = 12.dp)
                    )
                    if (loginError != null) {
                        Text(
                            text = loginError,
                            color = TierInstantClassic,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(top = 6.dp)
                        )
                    }
                    Row(modifier = Modifier.fillMaxWidth().padding(top = 14.dp), horizontalArrangement = Arrangement.End) {
                        OutlinedButton(onClick = onDismiss, enabled = !isLoggingIn) { Text("Cancel") }
                        Spacer(modifier = Modifier.width(8.dp))
                        Button(onClick = { onSubmitPin(pin) }, enabled = !isLoggingIn && pin.isNotEmpty()) {
                            if (isLoggingIn) {
                                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                            } else {
                                Text("Unlock")
                            }
                        }
                    }
                } else {
                    var url by remember { mutableStateOf("") }
                    var isSubmitting by remember { mutableStateOf(false) }
                    var submitError by remember { mutableStateOf<String?>(null) }
                    Text(
                        text = "Add highlights link",
                        color = TextPrimary,
                        style = MaterialTheme.typography.titleMedium
                    )
                    OutlinedTextField(
                        value = url,
                        onValueChange = { url = it },
                        placeholder = { Text("Paste a YouTube link", style = MaterialTheme.typography.bodySmall) },
                        singleLine = true,
                        enabled = !isSubmitting,
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedTextColor = TextPrimary,
                            unfocusedTextColor = TextPrimary,
                            focusedBorderColor = TierWorthYourTime,
                            unfocusedBorderColor = TextMuted
                        ),
                        modifier = Modifier.fillMaxWidth().padding(top = 12.dp)
                    )
                    if (submitError != null) {
                        Text(
                            text = submitError ?: "",
                            color = TierInstantClassic,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(top = 6.dp)
                        )
                    }
                    Row(modifier = Modifier.fillMaxWidth().padding(top = 14.dp), horizontalArrangement = Arrangement.End) {
                        OutlinedButton(onClick = onDismiss, enabled = !isSubmitting) { Text("Cancel") }
                        Spacer(modifier = Modifier.width(8.dp))
                        Button(
                            onClick = {
                                isSubmitting = true
                                submitError = null
                                onSubmitLink(
                                    url,
                                    { videoId -> onLinkSaved(videoId) },
                                    { message ->
                                        isSubmitting = false
                                        submitError = message
                                    }
                                )
                            },
                            enabled = !isSubmitting && url.isNotBlank()
                        ) {
                            if (isSubmitting) {
                                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                            } else {
                                Text("Save")
                            }
                        }
                    }
                }
            }
        }
    }
}
