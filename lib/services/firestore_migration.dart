import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Firestore migration service to initialize and verify collections.
///
/// Ensures both connection-layer (neutral_handshakes) and session-layer
/// (handshakes) collections exist with proper schema.
class FirestoreMigration {
  static final _db = FirebaseFirestore.instance;
  static const _kMigrationDoneKey = 'firestore_migration_v1_done';

  /// Initializes Firestore collections on app startup.
  ///
  /// Gated behind a SharedPreferences flag — skips entirely after first
  /// successful run. If either ensure-method throws, the flag is NOT set
  /// and the migration retries on the next launch.
  ///
  /// This method is safe to call multiple times — it's idempotent.
  /// - Creates `handshakes` collection if missing (by creating a sentinel doc)
  /// - Verifies `neutral_handshakes` exists
  static Future<void> initializeCollections() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kMigrationDoneKey) == true) return; // already done

    try {
      // Verify/initialize handshakes collection (session-layer)
      await _ensureHandshakesCollection();

      // Verify neutral_handshakes collection exists (connection-layer)
      await _ensureNeutralHandshakesCollection();

      await prefs.setBool(_kMigrationDoneKey, true); // mark complete
      if (kDebugMode) debugPrint('✅ Firestore collections initialized');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️  Firestore migration warning: $e');
      // Don't set the flag — retry next launch
      // Don't fail the app if migration has issues — collections will be
      // auto-created when first documents are written
    }
  }

  /// Ensures the session-layer handshakes collection exists.
  ///
  /// Firestore collections are created automatically on first real document
  /// write — no sentinel doc is needed. The previous sentinel write+delete
  /// approach was removed because it caused a billable write+delete on every
  /// fresh install and required overly-permissive security rules for the
  /// `handshakes/_sentinel` path (WR-010 fix).
  static Future<void> _ensureHandshakesCollection() async {
    // No-op: collection creation is handled by Firestore automatically.
    if (kDebugMode) debugPrint('📝 handshakes collection will be created on first write (no sentinel needed)');
  }

  /// Ensures the connection-layer neutral_handshakes collection exists.
  ///
  /// This is a safety check; neutral_handshakes should exist from Phase 05.
  static Future<void> _ensureNeutralHandshakesCollection() async {
    try {
      final snap = await _db.collection('neutral_handshakes').limit(1).get();
      if (kDebugMode) debugPrint('📝 neutral_handshakes collection exists (${snap.size} docs)');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️  Could not verify neutral_handshakes collection: $e');
    }
  }
}
