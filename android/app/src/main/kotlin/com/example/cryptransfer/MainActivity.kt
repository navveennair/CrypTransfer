package com.example.cryptransfer

import android.os.Bundle
import android.view.WindowManager.LayoutParams
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * CrypTransfer Android entry point.
 *
 * Native–Dart security bridge
 * ─────────────────────────────────────────────────────────────────────────────
 * Two native hooks are wired here and consumed by the Dart layer:
 *
 * 1. FLAG_SECURE (onCreate)
 *    Native:  window.addFlags(LayoutParams.FLAG_SECURE)
 *    Dart:    SecurityLifecycleMixin.isFlagSecureActive()
 *             → lib/core/utils/security_lifecycle_mixin.dart
 *    Purpose: Blocks task-switcher thumbnails and screenshots at the Android
 *             window level.  The Dart side queries this flag before each 64 KB
 *             chunk read to confirm the window is protected before sensitive
 *             bytes enter the Dart heap.
 *
 * 2. MethodChannel "com.example.cryptransfer/security" (configureFlutterEngine)
 *    Native:  returns (flags & FLAG_SECURE) != 0
 *    Dart:    SecurityLifecycleMixin._securityChannel.invokeMethod('isFlagSecureActive')
 *             → lib/core/utils/security_lifecycle_mixin.dart (static field _securityChannel)
 *    Purpose: Lets SenderScreen._encryptFile() abort if FLAG_SECURE is somehow
 *             inactive before processing begins.
 *             → lib/presentation/sender/sender_screen.dart
 */
class MainActivity : FlutterActivity() {

    // Channel name must match SecurityLifecycleMixin._securityChannel in
    // lib/core/utils/security_lifecycle_mixin.dart
    private val securityChannel = "com.example.cryptransfer/security"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block task-switcher thumbnails and screenshots — prevents key/file
        // content from leaking via the Android recents screen or screen capture.
        //
        // Dart counterpart: SecurityLifecycleMixin.isFlagSecureActive()
        //   lib/core/utils/security_lifecycle_mixin.dart
        // Queried by: SenderScreen._encryptFile() before each 64 KB chunk read
        //   lib/presentation/sender/sender_screen.dart
        window.addFlags(LayoutParams.FLAG_SECURE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Expose FLAG_SECURE status to the Dart layer so SecurityLifecycleMixin
        // can confirm the window is protected before processing 64 KB chunks.
        //
        // Consumed by: SecurityLifecycleMixin._securityChannel.invokeMethod('isFlagSecureActive')
        //   lib/core/utils/security_lifecycle_mixin.dart
        // Kill-switch context: EncryptionService.bindSession reacts to
        //   SessionState.terminated emitted by SessionManager.stateStream
        //   lib/data/services/encryption_service.dart
        //   lib/core/utils/session_manager.dart
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, securityChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isFlagSecureActive" -> {
                        val flags = window.attributes.flags
                        result.success((flags and LayoutParams.FLAG_SECURE) != 0)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
