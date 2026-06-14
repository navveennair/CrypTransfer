import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Centralised biometric / device-credential authentication helper.
///
/// Used by both [SenderScreen] and [ReceiverScreen] so auth behaviour is
/// consistent across the app.
class BiometricHelper {
  static final _auth = LocalAuthentication();

  /// Attempts biometric or device-credential authentication.
  ///
  /// Uses [LocalAuthentication.isDeviceSupported] as the guard:
  /// - If the device has ANY security lock (PIN/pattern/password/biometric),
  ///   calls [authenticate] with `biometricOnly: false` so the OS picks the
  ///   best available method (biometrics preferred, PIN/pattern as fallback).
  /// - If the device has NO security lock at all (factory-reset device,
  ///   emulator without PIN), passes through with a debug warning — no auth
  ///   is possible on such a device.
  ///
  /// Returns `false` on explicit user cancellation or failed attempt.
  static Future<bool> authenticate(String reason) async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      if (!isSupported) {
        // No security lock at all — pass through with a warning.
        if (kDebugMode) {
          debugPrint('[BiometricHelper] Device has no security lock — passing through');
        }
        return true;
      }
      if (kDebugMode) debugPrint('[BiometricHelper] authenticate: isSupported=true, calling _auth.authenticate');
      final result = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (kDebugMode) debugPrint('[BiometricHelper] authenticate() returned: $result');
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[BiometricHelper] authenticate() EXCEPTION: $e');
      return false;
    }
  }
}
