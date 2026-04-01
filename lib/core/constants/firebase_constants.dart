/// Single source of truth for all Firestore collection names,
/// Storage path prefixes, and secure-storage key names.
abstract class FirebaseConstants {
  // ─── Firestore collections ─────────────────────────────────────────────────
  static const String users = 'users';
  static const String transfers = 'transfers';
  static const String transfersLog = 'transfers_log';
  static const String notifications = 'notifications';
  static const String friendRequests = 'friend_requests';
  static const String rsaKeyTransfers = 'rsa_key_transfers';

  // ─── Firebase Storage paths ────────────────────────────────────────────────
  static const String transfersStorageRoot = 'transfers';
  static const String encryptedFileName = 'encrypted_file';

  // ─── Secure storage keys ───────────────────────────────────────────────────
  static const String privateKeyStorageKey = 'rsa_private_key';
  static const String publicKeyStoragePrefix = 'rsa_public_key_';

  // ─── Limits ───────────────────────────────────────────────────────────────
  static const int maxDownloadBytes = 100 * 1024 * 1024; // 100 MB
}
