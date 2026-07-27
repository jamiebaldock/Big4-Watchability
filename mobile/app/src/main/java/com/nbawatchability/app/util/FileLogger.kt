package com.nbawatchability.app.util

import android.content.Context
import android.os.Environment
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Logs performance and debug info to a file synced via Google Drive.
 * Writes to Downloads/NBA Watchability Logs/ which is accessible via
 * Google Drive or Files app.
 */
object FileLogger {
    private var logFile: File? = null
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
    private val filenameDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    fun init(context: Context) {
        try {
            // Write to Downloads folder (more reliable sync with Drive)
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val logsDir = File(downloadsDir, "NBA Watchability Logs")

            if (!logsDir.exists()) {
                logsDir.mkdirs()
            }

            val filename = "perf-${filenameDateFormat.format(Date())}.log"
            logFile = File(logsDir, filename)

            Log.d("FileLogger", "Logging to: ${logFile?.absolutePath}")
        } catch (e: Exception) {
            Log.e("FileLogger", "Failed to init file logger", e)
        }
    }

    fun log(tag: String, message: String) {
        // logcat first, unconditionally - the disk write below is a nice-
        // to-have (Drive-synced log for off-device inspection) that can
        // legitimately fail on newer Android versions' scoped storage even
        // with the legacy WRITE_EXTERNAL_STORAGE permission granted; it
        // used to be the other way around, which meant a failed disk write
        // silently swallowed the logcat line too (jumped straight to catch
        // before ever reaching Log.d) - every on-device PERF timing this
        // session had to work around by re-deriving durations from log
        // timestamps instead of the intended one-line-per-measurement output.
        Log.d(tag, message)
        try {
            val timestamp = dateFormat.format(Date())
            val line = "[$timestamp] $tag: $message\n"
            logFile?.appendText(line)
        } catch (e: Exception) {
            Log.e("FileLogger", "Failed to write log", e)
        }
    }

    fun logError(tag: String, message: String, throwable: Throwable? = null) {
        val fullMessage = if (throwable != null) {
            "$message\n${throwable.stackTraceToString()}"
        } else {
            message
        }
        log(tag, fullMessage)
    }
}
