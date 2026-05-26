import 'package:local_auth/local_auth.dart';

/// Centralised biometric / device-credential authentication helper.
///
/// Used by both [SenderScreen] and [ReceiverScreen] so auth behaviour is
/// consistent across the app.
class BiometricHelper {
  static final _auth = LocalAuthentication();

  /// Returns true if the device has enrolled biometric credentials
  /// (fingerprint, face, iris). Does NOT include PIN/pattern/password —
  /// those are not reliably available on emulators and cause silent failures.
  static Future<bool> checkBiometrics() async {
    try {
      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Attempts biometric authentication.
  ///
  /// Returns `true` on success or when no biometric hardware is enrolled
  /// (emulators, devices with PIN-only lock screens pass through).
  /// Returns `false` only on explicit user cancellation or failed attempt.
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
