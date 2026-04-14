import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'session_state.dart';

export 'session_state.dart';

/// Centralises receiver-session state transitions and the kill-switch handshake.
///
/// One instance is created per [ReceiverScreen] session.  UI widgets subscribe
/// to [stateNotifier] for real-time visual feedback without coupling to the
/// screen's internal state.
///
/// [stateStream] is a broadcast [Stream] of every [SessionState] transition.
/// [EncryptionService.bindSession] subscribes to it so that the crypto cleanup
/// ([closeReceiverSession]) fires automatically when state reaches
/// [SessionState.terminated] — no direct call from here required.
///
/// Kill-switch chain:
/// ```
/// AppLifecycleState.paused / detached
///       │
///       ▼
/// SessionManager.handleLifecycleState()
///       │
///       ▼
/// SessionManager.wipeSession()
///   ├── stateNotifier → SessionState.terminated
///   ├── stateStream   → SessionState.terminated  ←── EncryptionService listener
///   │       └── EncryptionService.closeReceiverSession()  [Firestore + SecureStorage]
///   └── onBuffersWipe()  [SecurityLifecycleMixin.wipeAll — zeroes Uint8List]
/// ```
class SessionManager {
  final ValueNotifier<SessionState> stateNotifier =
      ValueNotifier(SessionState.open);

  final _stateStreamController =
      StreamController<SessionState>.broadcast();

  /// Broadcast stream of every [SessionState] transition.
  ///
  /// [EncryptionService.bindSession] subscribes here so that crypto key
  /// cleanup fires reactively when state transitions to
  /// [SessionState.terminated], rather than being triggered by a direct
  /// imperative call.
  Stream<SessionState> get stateStream => _stateStreamController.stream;

  // ─── Session isolation ────────────────────────────────────────────────────

  /// UID of the single sender selected for this session.
  /// Non-null once the receiver picks a sender from the Find Sender sheet.
  /// Cleared on [reset] and [wipeSession].
  String? activeSenderUid;

  /// Display username that pairs with [activeSenderUid].
  String? activeSenderUsername;

  /// Lock in a sender for this session.  Only one sender is permitted at a
  /// time — call [clearSender] (or [reset]) before selecting a different one.
  void selectSender(String uid, String username) {
    activeSenderUid = uid;
    activeSenderUsername = username;
  }

  /// Remove the active sender selection without changing [SessionState].
  void clearSender() {
    activeSenderUid = null;
    activeSenderUsername = null;
  }

  SessionState get state => stateNotifier.value;

  // ─── Transitions ─────────────────────────────────────────────────────────

  /// Transition to [SessionState.locked] when an incoming transfer arrives.
  void lock() => _set(SessionState.locked);

  /// Transition to [SessionState.decrypting] when the decrypt phase begins.
  void setDecrypting() => _set(SessionState.decrypting);

  /// Return to [SessionState.open] after a clean mailbox close or session reset.
  void reset() {
    clearSender();
    _set(SessionState.open);
  }

  void _set(SessionState next) {
    if (stateNotifier.value != next) {
      stateNotifier.value = next;
      _stateStreamController.add(next);
    }
  }

  // ─── Kill switch ─────────────────────────────────────────────────────────

  /// Wipes all active keys and marks the session [SessionState.terminated].
  ///
  /// The [SessionState.terminated] transition is emitted on [stateStream],
  /// which [EncryptionService.bindSession] listens to — Firestore public key
  /// deletion and SecureStorage private key wipe happen reactively via that
  /// binding rather than via a direct call here.
  ///
  /// Idempotent — subsequent calls are no-ops once terminated.
  ///
  /// [onBuffersWipe]  — callback into [SecurityLifecycleMixin.wipeAll]; zeroes
  ///                    all registered in-memory [Uint8List] buffers on the
  ///                    calling screen.
  void wipeSession({required VoidCallback onBuffersWipe}) {
    if (stateNotifier.value == SessionState.terminated) return;
    clearSender();
    _set(SessionState.terminated); // → stateStream fires → EncryptionService reacts
    onBuffersWipe();
  }

  // ─── Lifecycle handshake ─────────────────────────────────────────────────

  /// Kill-switch handshake wired to [ReceiverScreen.didChangeAppLifecycleState].
  ///
  /// Fires [wipeSession] only on [AppLifecycleState.paused] or
  /// [AppLifecycleState.detached]; all other states are ignored.
  void handleLifecycleState(
    AppLifecycleState lifecycle, {
    required VoidCallback onBuffersWipe,
  }) {
    if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.detached) {
      wipeSession(onBuffersWipe: onBuffersWipe);
    }
  }

  // ─── Cleanup ─────────────────────────────────────────────────────────────

  void dispose() {
    stateNotifier.dispose();
    _stateStreamController.close();
  }
}
