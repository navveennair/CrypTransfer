import 'dart:typed_data';

import 'package:flutter/material.dart';

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
  final List<Uint8List> _radioactiveBuffers = [];

  /// Register a buffer for automatic zeroing.
  /// Call this immediately after any sensitive [Uint8List] is created.
  void registerBuffer(Uint8List buffer) {
    _radioactiveBuffers.add(buffer);
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
