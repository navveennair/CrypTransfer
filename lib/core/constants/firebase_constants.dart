/// Single source of truth for all Firestore collection names,
/// Storage path prefixes, and secure-storage key names.
abstract class FirebaseConstants {
  // ─── Firestore collections ─────────────────────────────────────────────────
  static const String users = 'users';
  static const String transfers = 'transfers';
  static const String transferLogs = 'transfer_logs';
  static const String auditLogs = 'audit_logs';
  static const String notifications = 'notifications';
  static const String friendRequests = 'friend_requests';
  static const String connections = 'connections';
  static const String friendships = 'friendships';
  static const String handshakes = 'handshakes';
  static const String securityAuditLog = 'security_audit_log';
  static const String rsaKeyManager = 'rsa_key_manager';  // subcollection: users/{uid}/rsa_key_manager
  static const String profile = 'profile';                 // subcollection: users/{uid}/profile

  // ─── Firebase Storage paths ────────────────────────────────────────────────
  static const String transfersStorageRoot = 'transfers';
  static const String encryptedFileName = 'encrypted_file';

  // ─── Secure storage keys ───────────────────────────────────────────────────
  static const String privateKeyStorageKey = 'rsa_private_key';
  static const String publicKeyStoragePrefix = 'rsa_public_key_';

  // ─── Google Sign-In ───────────────────────────────────────────────────────
  // Firebase Console → Authentication → Sign-in method → Google →
  // Web SDK configuration → Web client ID
  static const String googleWebClientId =
      '881677813575-de8cqucd3qd71cbfk3rrb8l65osff7vc.apps.googleusercontent.com';

  // ─── Limits ───────────────────────────────────────────────────────────────
  static const int maxDownloadBytes = 100 * 1024 * 1024; // 100 MB
}
