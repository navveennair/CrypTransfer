package com.example.cryptransfer

import android.content.ContentValues
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.WindowManager.LayoutParams
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * CrypTransfer Android entry point.
 *
 * Native–Dart security bridge
 * ─────────────────────────────────────────────────────────────────────────────
 * Channel 1 — "com.example.cryptransfer/security"
 *   isFlagSecureActive  → returns (flags & FLAG_SECURE) != 0
 *   clearSession        → System.gc() hint (no key bytes held natively)
 *   Consumed by: SecurityLifecycleMixin  (lib/core/utils/security_lifecycle_mixin.dart)
 *
 * Channel 2 — "com.example.cryptransfer/file"
 *   saveToDownloads(fileName, bytes) → saves to public Downloads folder
 *     Android 10+ : MediaStore.Downloads (no WRITE_EXTERNAL_STORAGE needed)
 *     Android <10 : direct FileOutputStream (needs WRITE_EXTERNAL_STORAGE)
 *   Consumed by: DecryptScreen._saveAndWipe()  (lib/presentation/receiver/decrypt_screen.dart)
 */
class MainActivity : FlutterActivity() {

    private val securityChannel = "com.example.cryptransfer/security"
    private val fileChannel     = "com.example.cryptransfer/file"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block task-switcher thumbnails and screenshots across all Flutter screens.
        // Dart counterpart: SecurityLifecycleMixin.isFlagSecureActive()
        window.addFlags(LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Security channel ──────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, securityChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isFlagSecureActive" -> {
                        val flags = window.attributes.flags
                        result.success((flags and LayoutParams.FLAG_SECURE) != 0)
                    }
                    "clearSession" -> {
                        // No RSA/AES bytes held natively — all crypto in Dart compute() isolates.
                        Thread { System.gc() }.start()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── File channel ──────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val fileName = call.argument<String>("fileName") ?: ""
                        val bytes    = call.argument<ByteArray>("bytes")
                        if (bytes == null || fileName.isEmpty()) {
                            result.error("INVALID_ARGS", "fileName and bytes required", null)
                            return@setMethodCallHandler
                        }
                        // Run on background thread — MediaStore I/O must not block the UI thread.
                        Thread {
                            try {
                                val path = saveToDownloads(fileName, bytes)
                                runOnUiThread { result.success(path) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SAVE_FAILED", e.message, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Saves [bytes] as [fileName] in the public Downloads folder.
     *
     * Android 10+ (API 29+): uses MediaStore.Downloads — no storage permission required.
     * Android  <10 (API 28-): writes directly to DIRECTORY_DOWNLOADS — requires
     *   WRITE_EXTERNAL_STORAGE (declared in AndroidManifest with maxSdkVersion="28").
     */
    private fun saveToDownloads(fileName: String, bytes: ByteArray): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = applicationContext.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw Exception("MediaStore could not create Downloads entry")
            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw Exception("Could not open MediaStore output stream")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            "${Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS).absolutePath}/$fileName"
        } else {
            val file = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                fileName
            )
            FileOutputStream(file).use { it.write(bytes) }
            file.absolutePath
        }
    }
}
