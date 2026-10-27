package com.example.buid_arch

import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

class MainActivity : FlutterFragmentActivity() {
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSourceFile: File? = null
    private var pendingSharedText: String? = null
    private var sharedLocationChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        pendingSharedText = sharedTextFrom(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sharedLocationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARED_LOCATION_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "takeSharedText") {
                    result.success(pendingSharedText)
                    pendingSharedText = null
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FILE_SAVER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "saveDownloadedFile") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            if (pendingSaveResult != null) {
                result.error("save_in_progress", "A file save is already in progress.", null)
                return@setMethodCallHandler
            }

            val sourcePath = call.argument<String>("sourcePath")
            val fileName = call.argument<String>("fileName")
            val mimeType = call.argument<String>("mimeType")
            if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                result.error("invalid_arguments", "A file path and name are required.", null)
                return@setMethodCallHandler
            }

            val sourceFile = File(sourcePath).canonicalFile
            val cachePath = cacheDir.canonicalPath + File.separator
            if (!sourceFile.path.startsWith(cachePath) || !sourceFile.isFile) {
                result.error("invalid_file", "The downloaded file is unavailable.", null)
                return@setMethodCallHandler
            }

            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = mimeType?.takeIf(String::isNotBlank) ?: "*/*"
                putExtra(Intent.EXTRA_TITLE, fileName)
            }
            pendingSaveResult = result
            pendingSourceFile = sourceFile
            try {
                startActivityForResult(intent, SAVE_FILE_REQUEST_CODE)
            } catch (error: Exception) {
                pendingSaveResult = null
                pendingSourceFile = null
                result.error("save_picker_failed", "Could not open the save dialog.", error.message)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingSharedText = sharedTextFrom(intent)
        val channel = sharedLocationChannel
        if (channel != null) {
            pendingSharedText?.let { sharedText ->
                channel.invokeMethod("sharedTextReceived", sharedText)
            }
        }
    }

    private fun sharedTextFrom(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND ||
            intent.type?.startsWith("text/") != true
        ) {
            return null
        }
        return intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
            ?.toString()
            ?.takeIf(String::isNotBlank)
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_FILE_REQUEST_CODE) return

        val result = pendingSaveResult ?: return
        val sourceFile = pendingSourceFile
        pendingSaveResult = null
        pendingSourceFile = null

        val destination = data?.data
        if (resultCode != RESULT_OK || destination == null || sourceFile == null) {
            result.success(false)
            return
        }

        Thread {
            try {
                val output = contentResolver.openOutputStream(destination)
                    ?: throw IOException("Could not open the selected destination.")
                sourceFile.inputStream().buffered().use { input ->
                    output.buffered().use { stream -> input.copyTo(stream) }
                }
                mainHandler.post { result.success(true) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error("save_failed", "Could not save the downloaded file.", error.message)
                }
            }
        }.start()
    }

    companion object {
        private const val FILE_SAVER_CHANNEL = "com.example.buid_arch/project_file_saver"
        private const val SHARED_LOCATION_CHANNEL = "com.example.buid_arch/shared_location"
        private const val SAVE_FILE_REQUEST_CODE = 9317
    }
}
