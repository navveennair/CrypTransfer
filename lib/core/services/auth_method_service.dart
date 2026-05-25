import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pointycastle/pointycastle.dart';

enum AuthMethod { biometric, pin, none }

class AuthMethodService {
  static const _storage = FlutterSecureStorage();
  static const _pinHashKey = 'auth_pin_hash';
  static const _methodKey = 'auth_preferred_method';
  static final _auth = LocalAuthentication();

  static Future<AuthMethod> getPreferredMethod() async {
    final val = await _storage.read(key: _methodKey);
    return switch (val) {
      'biometric' => AuthMethod.biometric,
      'pin' => AuthMethod.pin,
      _ => AuthMethod.none,
    };
  }

  static Future<void> setPreferredMethod(AuthMethod method) async {
    await _storage.write(
      key: _methodKey,
      value: switch (method) {
        AuthMethod.biometric => 'biometric',
        AuthMethod.pin => 'pin',
        AuthMethod.none => 'none',
      },
    );
  }

  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) return [];
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> hasPin() async {
    final hash = await _storage.read(key: _pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  static Future<void> setPin(String pin) async {
    await _storage.write(key: _pinHashKey, value: _sha256(pin));
  }

  static Future<bool> verifyPin(String pin) async {
    final stored = await _storage.read(key: _pinHashKey);
    if (stored == null) return false;
    return _sha256(pin) == stored;
  }

  static Future<void> clearPin() async {
    await _storage.delete(key: _pinHashKey);
  }

  static String _sha256(String input) {
    final digest = Digest('SHA-256');
    final bytes = Uint8List.fromList(utf8.encode(input));
    return base64Url.encode(digest.process(bytes));
  }
}
