/// Single source of truth for all Firestore collection names,
/// Storage path prefixes, and secure-storage key names.
abstract class FirebaseConstants {
  // ─── Firestore collections ─────────────────────────────────────────────────
  static const String users = 'users';
  static const String transfers = 'transfers';
  static const String auditLogs = 'audit_logs';
  static const String notifications = 'notifications';
  static const String friendships = 'friendships';  // subcollection: users/{uid}/friendships

  // Connection layer: initial proposals (symmetric roles)
  static const String neutralHandshakes = 'neutral_handshakes';

  // Session layer: RSA key exchange + role assignment (asymmetric sender/receiver)
  static const String roleHandshakes = 'role_handshake';
  static const String transferLogs = 'transfer_logs';
  static const String securityAuditLog = 'security_audit_log';
  static const String rsaKeyManager = 'rsa_key_manager';  // subcollection: users/{uid}/rsa_key_manager
  static const String profile = 'profile';                 // subcollection: users/{uid}/profile

  // ─── User document fields ──────────────────────────────────────────────────
  static const String pendingSenderFor = 'pendingSenderFor';     // set when user claims sender role toward a partner; cleared on exit
  static const String pendingReceiverFor = 'pendingReceiverFor'; // set when user claims receiver role toward a partner; cleared on exit

  // ─── Firebase Storage paths ────────────────────────────────────────────────
  static const String transfersStorageRoot = 'transfers';
  static const String encryptedFileName = 'encrypted_file';

  // ─── Secure storage keys ───────────────────────────────────────────────────
  static const String privateKeyStorageKey = 'rsa_private_key';
  static const String publicKeyStoragePrefix = 'rsa_public_key_';

  // ─── Limits ───────────────────────────────────────────────────────────────
  static const int maxDownloadBytes = 100 * 1024 * 1024; // 100 MB
}
