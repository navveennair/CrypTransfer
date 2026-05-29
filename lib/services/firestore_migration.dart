// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore migration service to initialize and verify collections.
///
/// Ensures both connection-layer (neutral_handshakes) and session-layer
/// (handshakes) collections exist with proper schema.
class FirestoreMigration {
  static final _db = FirebaseFirestore.instance;

  /// Initializes Firestore collections on app startup.
  ///
  /// This method is safe to call multiple times — it's idempotent.
  /// - Creates `handshakes` collection if missing (by creating a sentinel doc)
  /// - Verifies `neutral_handshakes` exists
  static Future<void> initializeCollections() async {
    try {
      // Verify/initialize handshakes collection (session-layer)
      await _ensureHandshakesCollection();

      // Verify neutral_handshakes collection exists (connection-layer)
      await _ensureNeutralHandshakesCollection();

      print('✅ Firestore collections initialized');
    } catch (e) {
      print('⚠️  Firestore migration warning: $e');
      // Don't fail the app if migration has issues — collections will be
      // auto-created when first documents are written
    }
  }

  /// Ensures the session-layer handshakes collection exists.
  ///
  /// Creates a temporary sentinel document if the collection is empty.
  /// This triggers Firestore to create the collection and apply security rules.
  static Future<void> _ensureHandshakesCollection() async {
    try {
      final snap = await _db.collection('handshakes').limit(1).get();
      if (snap.docs.isEmpty) {
        // Collection doesn't exist yet — create a sentinel doc to initialize it
        final sentinelRef = _db.collection('handshakes').doc('_sentinel');
        await sentinelRef.set({
          'type': 'sentinel',
          'createdAt': FieldValue.serverTimestamp(),
          'note': 'Auto-created to initialize collection schema',
        });
        // Delete the sentinel immediately
        await sentinelRef.delete();
        print('📝 Initialized handshakes collection (session-layer)');
      } else {
        print('📝 handshakes collection already exists');
      }
    } catch (e) {
      print('⚠️  Could not verify handshakes collection: $e');
    }
  }

  /// Ensures the connection-layer neutral_handshakes collection exists.
  ///
  /// This is a safety check; neutral_handshakes should exist from Phase 05.
  static Future<void> _ensureNeutralHandshakesCollection() async {
    try {
      final snap = await _db.collection('neutral_handshakes').limit(1).get();
      print('📝 neutral_handshakes collection exists (${snap.size} docs)');
    } catch (e) {
      print('⚠️  Could not verify neutral_handshakes collection: $e');
    }
  }
}
