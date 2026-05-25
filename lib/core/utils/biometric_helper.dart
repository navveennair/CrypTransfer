import 'package:local_auth/local_auth.dart';

/// Centralised biometric / device-credential authentication helper.
///
/// Used by both [SenderScreen] and [ReceiverScreen] so auth behaviour is
/// consistent across the app.
class BiometricHelper {
  static final _auth = LocalAuthentication();

  /// Returns true if the device can perform any form of authentication
  /// (fingerprint, face, iris, PIN, pattern, password).
  static Future<bool> checkBiometrics() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Attempts to authenticate the user.
  ///
  /// Falls through to PIN / pattern when biometrics are unavailable.
  /// Returns `true` on success or when the device has no auth hardware.
  /// Returns `false` on failure or cancellation.
  static Future<bool> authenticate(String reason) async {
    try {
      final canAuth = await checkBiometrics();
      if (!canAuth) return true;
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
