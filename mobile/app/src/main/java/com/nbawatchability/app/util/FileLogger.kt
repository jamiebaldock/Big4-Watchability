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
        try {
            val timestamp = dateFormat.format(Date())
            val line = "[$timestamp] $tag: $message\n"

            logFile?.appendText(line)
            Log.d(tag, message)
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
