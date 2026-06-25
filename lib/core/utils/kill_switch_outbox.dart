import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/encryption_service.dart';

/// Persistent outbox for incomplete kill-switch cleanup operations.
///
/// [closeReceiverSession] performs multiple sequential Firestore round-trips.
/// If the device loses network mid-sequence, some cleanup steps (handshake
/// deletes, transfer deletes, notification deletes) may be skipped, leaving
/// orphaned documents. This outbox closes that gap:
///
/// 1. [persist] is called at the top of [closeReceiverSession] — **before**
///    any Firestore writes — to durably record that cleanup is in progress.
/// 2. [clear] is called at the end of [closeReceiverSession] on success.
/// 3. [resumeIfPending] is called from [main] on every app launch. If a
///    record exists for the currently authenticated user, it re-runs
///    [closeReceiverSession], which is fully idempotent (deleting already-
///    deleted docs is a no-op; SecureStorage delete on a missing key is safe).
///
/// A record left by a *different* user (e.g. after account switch) is
/// discarded without attempting cleanup — Firestore rules would reject it.
class KillSwitchOutbox {
  static const _kKey = 'pending_kill_switch_v1';

  /// Write a pending cleanup record. Call this before any Firestore ops.
  static Future<void> persist(String uid, String? selectedSenderUid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kKey,
      jsonEncode({
        'uid': uid,
        'selectedSenderUid': selectedSenderUid ?? '',
        'persistedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  /// Remove the pending record after cleanup completes successfully.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKey);
  }

  /// On app launch, check for an incomplete kill-switch and resume if the
  /// same authenticated user is present.
  ///
  /// [currentUid] defaults to [FirebaseAuth.instance.currentUser]'s uid;
  /// overridable in tests since [FirebaseAuth.instance] cannot itself be
  /// mocked (it's a real static singleton, not constructor-injectable).
  static Future<void> resumeIfPending({String? currentUid}) async {
    final uid = currentUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      await clear();
      return;
    }

    final recordUid = data['uid'] as String?;
    if (recordUid == null || recordUid.isEmpty || recordUid != uid) {
      // Stale record from a different session or corrupt data — discard.
      await clear();
      return;
    }

    if (kDebugMode) {
      debugPrint('[KillSwitchOutbox] Found incomplete kill-switch for $uid — resuming cleanup.');
    }

    try {
      await EncryptionService.closeReceiverSession(uid);
      // closeReceiverSession calls KillSwitchOutbox.clear() on success.
    } catch (e) {
      // Still offline — leave the record for the next launch.
      if (kDebugMode) {
        debugPrint('[KillSwitchOutbox] Resume failed (still offline?): $e');
      }
    }
  }
}
