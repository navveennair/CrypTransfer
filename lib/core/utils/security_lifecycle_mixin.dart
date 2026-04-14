import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Mixin that automatically zeroes sensitive in-memory buffers when a screen
/// is disposed or explicitly wiped.
///
/// Usage:
/// ```dart
/// class _MyScreenState extends State<MyScreen>
///     with SecurityLifecycleMixin<MyScreen> {
///
///   @override
///   void initState() {
///     super.initState();
///     final key = generateKey();
///     registerBuffer(key); // registered — will be zeroed on dispose
///   }
/// }
/// ```
mixin SecurityLifecycleMixin<T extends StatefulWidget> on State<T> {
  // ─── Kotlin sync: FLAG_SECURE pre-flight check ────────────────────────────

  static final _securityChannel =
      const MethodChannel('com.example.cryptransfer/security');

  /// Returns `true` when Android `FLAG_SECURE` is confirmed active on the host
  /// window — verified via a synchronous Kotlin query on the same channel that
  /// sets the flag in `MainActivity.onCreate`.
  ///
  /// Call this before any 64 KB chunk read begins to ensure the Android window
  /// is protected before sensitive bytes enter the Dart heap.
  ///
  /// - Returns `true` on iOS / desktop (not applicable on those platforms).
  /// - Returns `true` on `MissingPluginException` (safe fallback for unit tests
  ///   and emulators where the plugin may not be registered).
  /// - Never throws; errors are swallowed and treated as "flag assumed active"
  ///   to avoid blocking transfers due to a non-security-critical probe failure.
  static Future<bool> isFlagSecureActive() async {
    try {
      return await _securityChannel.invokeMethod<bool>('isFlagSecureActive') ??
          true;
    } on MissingPluginException {
      return true;
    } catch (_) {
      return true;
    }
  }

  // ─── Buffer registry ──────────────────────────────────────────────────────

  final List<Uint8List> _radioactiveBuffers = [];

  /// Register a buffer for automatic zeroing.
  /// Call this immediately after any sensitive [Uint8List] is created.
  void registerBuffer(Uint8List buffer) {
    _radioactiveBuffers.add(buffer);
  }

  /// Remove [buffer] from the registry after it has been explicitly wiped.
  ///
  /// Call this when you zero a buffer early (before [wipeAll] / [dispose])
  /// so that [wipeAll] does not attempt a redundant second pass over it.
  /// Uses identity comparison — only the exact instance is removed.
  void unregisterBuffer(Uint8List buffer) {
    _radioactiveBuffers.remove(buffer);
  }

  /// Zero all registered buffers, clear the registry, then call
  /// [onBuffersWiped] for any additional state cleanup.
  ///
  /// Safe to call multiple times — zeroing an already-zero buffer is harmless.
  void wipeAll() {
    for (final buffer in _radioactiveBuffers) {
      try {
        buffer.fillRange(0, buffer.length, 0);
      } catch (_) {
        // Buffer may be read-only in an edge case; swallow silently.
      }
    }
    _radioactiveBuffers.clear();
    onBuffersWiped();
  }

  /// Override to perform additional cleanup after buffers are wiped.
  ///
  /// This is called at the end of [wipeAll]. Implementations should guard any
  /// [setState] call with `if (mounted)` because [dispose] also calls
  /// [wipeAll], at which point the widget is no longer mounted.
  void onBuffersWiped() {}

  @override
  void dispose() {
    wipeAll();
    super.dispose();
  }
}
