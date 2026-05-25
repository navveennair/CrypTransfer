import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/repositories/auth_repository.dart';

enum TofuStatus {
  firstContact, // no pin stored — new receiver, blind trust
  trusted,      // pin matches, user has not explicitly verified
  verified,     // pin matches AND user tapped "It matches"
  keyChanged,   // stored pin does not match current key — BLOCK
}

/// Trust-On-First-Use key pinning for receiver identity.
///
/// On first send: pin SHA-256(publicKey) in FlutterSecureStorage.
/// On every subsequent send: compare pinned fingerprint to live key.
/// Key change → block transfer until user explicitly re-verifies.
class TofuService {
  static const _storage = FlutterSecureStorage();

  static String _pinKey(String uid) => 'tofu_pin_$uid';
  static String _verKey(String uid) => 'tofu_ver_$uid';

  /// Full 64-char SHA-256 hex. Delegates to AuthRepository so vault and
  /// sender display the same value for the same key.
  static String fingerprint(String publicKeyJson) =>
      AuthRepository.computeFingerprint(publicKeyJson);

  /// 16-char uppercase grouped display form: "AB12 CD34 EF56 7890".
  static String displayFingerprint(String publicKeyJson) {
    final hex = fingerprint(publicKeyJson).substring(0, 16).toUpperCase();
    return [hex.substring(0, 4), hex.substring(4, 8),
            hex.substring(8, 12), hex.substring(12, 16)].join(' ');
  }

  /// Check the TOFU status for [receiverUid] against [publicKeyJson].
  static Future<TofuStatus> check(
      String receiverUid, String publicKeyJson) async {
    final pinned = await _storage.read(key: _pinKey(receiverUid));
    if (pinned == null) return TofuStatus.firstContact;
    if (pinned != fingerprint(publicKeyJson)) return TofuStatus.keyChanged;
    final ver = await _storage.read(key: _verKey(receiverUid));
    return ver == '1' ? TofuStatus.verified : TofuStatus.trusted;
  }

  /// Store fingerprint on first contact.
  static Future<void> pin(String receiverUid, String publicKeyJson) =>
      _storage.write(
        key: _pinKey(receiverUid),
        value: fingerprint(publicKeyJson),
      );

  /// Mark as explicitly verified by the user.
  static Future<void> markVerified(String receiverUid) =>
      _storage.write(key: _verKey(receiverUid), value: '1');

  /// Accept a key change after re-verification. Clears verified flag —
  /// user must re-verify the new key explicitly.
  static Future<void> repin(String receiverUid, String publicKeyJson) async {
    await _storage.write(
      key: _pinKey(receiverUid),
      value: fingerprint(publicKeyJson),
    );
    await _storage.delete(key: _verKey(receiverUid));
  }
}
