# Coding Conventions

**Analysis Date:** 2025-04-19

## Naming Patterns

**Files:**
- Stateful widget files: lowercase_snake_case (e.g., `sender_screen.dart`, `receiver_screen.dart`)
- Service/repository files: lowercase_snake_case (e.g., `encryption_service.dart`, `auth_repository.dart`)
- Model files: lowercase_snake_case (e.g., `user_model.dart`, `transfer_model.dart`)
- Utilities/helpers: lowercase_snake_case (e.g., `session_manager.dart`, `security_lifecycle_mixin.dart`)

**Classes:**
- StatefulWidget classes: PascalCase (e.g., `SenderScreen`, `ReceiverScreen`, `EncryptionService`)
- State classes: `_WidgetNameState` convention (e.g., `_SenderScreenState`, `_ReceiverScreenState`)
- Service/Repository classes: PascalCase (e.g., `AuthRepository`, `KeyRepository`, `EncryptionService`)
- Custom widgets: PascalCase (e.g., `StepCard`, `CrypButton`, `UserAvatar`)
- Nested internal widget classes: PascalCase with leading underscore (e.g., `_KeyGenDialog`, `_FindSenderSheet`, `_ReceivedKeyCard`)

**Functions:**
- Instance methods: camelCase (e.g., `_onToggleReady()`, `_handleIncomingTransfer()`, `_checkKeyStatus()`)
- Private methods: leading underscore (e.g., `_encryptFile()`, `_revertToWaiting()`, `_onSessionStateChanged()`)
- Event handlers: `_onEventName()` pattern (e.g., `_onSenderSelected()`, `_onToggleReady()`, `_onHandshakeUpdate()`)
- Top-level isolate functions: leading underscore or descriptive name (e.g., `_generateRsaKeyPairIsolate()`, `runAesGcmEncrypt()`)

**Variables:**
- Private fields: leading underscore (e.g., `_authService`, `_sessionManager`, `_encryptedBytes`)
- Stream/Subscription fields: `_fieldNameSub` or `_fieldNameStream` (e.g., `_handshakeSub`, `_transferStream`)
- State flags: boolean prefix (e.g., `_isReadyToReceive`, `_handshakeDone`, `_sessionLocked`)
- UI state: `_step0Done`, `_step1Done` for step completion tracking

**Types & Enums:**
- Exception classes: `[Name]Exception` (e.g., `AuthException`, `CryptoException`, `NetworkException`)
- Enums: PascalCase (e.g., `SessionState`, `TransferStatus`, `NotificationType`, `_Phase`, `_Status`)
- Data classes: PascalCase (e.g., `AesEncryptResult`, `UserModel`)

## Code Style

**Formatting:**
- Dart convention: 2-space indentation (enforced by Flutter tooling)
- Line length: Soft limit ~100 chars (Flutter analyzer default)
- Trailing commas: Used for multi-line constructs (e.g., constructor arguments spanning lines)

**Linting:**
- Framework: Flutter lints via `package:flutter_lints/flutter.yaml` (`analysis_options.yaml`)
- Enabled rules: Standard Flutter recommendations (avoid_print suppressed for debug logging)
- Run checks: `flutter analyze`

**Formatting Tool:**
- Dart formatter via `dart format .` or IDE integration

## Import Organization

**Order:**
1. Dart imports (`dart:async`, `dart:convert`, `dart:typed_data`, etc.)
2. Flutter imports (`package:flutter/material.dart`, `package:flutter/foundation.dart`)
3. Package/plugin imports (`package:firebase_*`, `package:pointycastle`, `package:google_fonts`)
4. Relative imports (`import '../../core/...`, `import '../widgets/...'`)

**Path Aliases:**
- No aliases configured; uses relative imports throughout (e.g., `import '../../core/constants/firebase_constants.dart'`)

**Exports:**
- Minimal use of `export` statements; one example in `lib/core/utils/session_manager.dart`:
  ```dart
  export 'session_state.dart';
  ```
  This allows consumers of `SessionManager` to access the `SessionState` enum without separate import.

## Error Handling

**Patterns:**
- **Typed exceptions:** Domain-specific exception hierarchy in `lib/core/errors/app_exceptions.dart`:
  - `AppException` — base exception with `message` and optional `code`
  - `AuthException` — Firebase Auth / registration failures
  - `TransferException` — transfer document operation failures
  - `CryptoException` — RSA/AES encryption/decryption failures
  - `NetworkException` — Firestore/Storage network failures
  - `KeyNotFoundException` — missing RSA private/public keys

- **Cryptographic operations:** Wrapped in try-catch blocks with exception re-throws:
  ```dart
  static Uint8List rsaEncrypt(RSAPublicKey publicKey, Uint8List data) {
    try {
      final cipher = OAEPEncoding(RSAEngine())..init(true, ...);
      return cipher.process(data);
    } catch (e) {
      throw CryptoException('RSA encryption failed: $e');
    }
  }
  ```

- **Firestore operations:** Wrapped in try-catch blocks with security event logging:
  ```dart
  static Future<void> setupReceiverSession(String uid) async {
    try {
      // operation
    } catch (e) {
      _logSecurityEvent('setupReceiverSession_FAILED', uid, e.toString());
      rethrow;
    }
  }
  ```

- **UI error display:** SnackBars for user-facing errors; console logging for debug:
  ```dart
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Error message'),
      backgroundColor: Colors.orange.shade700,
    ),
  );
  ```

## Logging

**Framework:** Console/print + Firebase custom security event logging

**Patterns:**
- **Debug info:** `// ignore: avoid_print` + `print()` for development (see analysis_options.yaml)
- **Security events:** Custom logging via `EncryptionService._logSecurityEvent()` — writes to Firestore `security_events` collection with `uid`, `eventType`, `eventData`, `timestamp`
- **Test output:** `// ignore: avoid_print` + `print('✅ TC-WIPE-001 PASSED: ...')` for test case results

**Example from `lib/data/services/encryption_service.dart`:**
```dart
static void _logSecurityEvent(String eventType, String uid, String details) {
  try {
    FirebaseFirestore.instance
        .collection(FirebaseConstants.securityEvents)
        .add({
      'uid': uid,
      'eventType': eventType,
      'eventData': details,
      'timestamp': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    // ignore: avoid_print
    print('[SECURITY LOG ERROR] Could not write event: $e');
  }
}
```

## Comments

**When to Comment:**
- **High-level explanation:** Section dividers with clear intent (e.g., `// ─── Step 0: Receiver-Authorized connection`)
- **Non-obvious logic:** Complex cryptographic algorithms or state machine transitions
- **API documentation:** Public methods (repository, service) with `///` JSDoc-style comments
- **Todos/Known issues:** `// TODO`, `// FIXME` for tracked work (checked by Guardian scanner)

**JSDoc/TSDoc:**
- Used extensively for public APIs — repository methods, service methods, mixin definitions
- Format: `///` for doc comments on methods and classes:
  ```dart
  /// Centralises receiver-session state transitions and the kill-switch handshake.
  ///
  /// One instance is created per [ReceiverScreen] session.  UI widgets subscribe
  /// to [stateNotifier] for real-time visual feedback without coupling to the
  /// screen's internal state.
  class SessionManager { ... }
  ```

## Function Design

**Size:**
- Keep functions focused — 30–50 lines typical, max ~200 for complex screens
- Extract large blocks into private helper methods (e.g., `_step0Content()`, `_step1Content()`, `_step2Content()` in sender/receiver screens)

**Parameters:**
- Use named parameters for optional values; positional for required ones
- Constructor injection for dependencies (e.g., `AuthRepository` with optional `auth`, `db`, `secure` params):
  ```dart
  AuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    FlutterSecureStorage? secure,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _db = db ?? FirebaseFirestore.instance,
       _secure = secure ?? const FlutterSecureStorage();
  ```

**Return Values:**
- Futures for async operations: `Future<UserCredential>`, `Future<void>`
- Typed data: `Uint8List` for crypto material, `String` for serialized keys
- Enums for state: `SessionState` for kill-switch state machine

## Module Design

**Exports:**
- Stateful widgets export themselves (no public service/repo exports)
- Mixins exported explicitly: `export 'session_state.dart'` from `session_manager.dart`

**Barrel Files:**
- Not used; imports are explicit and hierarchical

**Mixin Application:**
- `SecurityLifecycleMixin<T extends StatefulWidget>` applied to screens that handle sensitive data:
  - Provides `registerBuffer()`, `unregisterBuffer()`, `wipeAll()` for zero-ing Uint8List
  - Applied to: `SenderScreen`, `ReceiverScreen`, `TransferProgressScreen`, `DownloadConfirmScreen`, `EndSessionScreen`, `DecryptScreen`
  - See `lib/core/utils/security_lifecycle_mixin.dart`

**Service Pattern:**
- Stateless services with static or instance methods:
  - `EncryptionService` — static methods for crypto (singleton behavior)
  - Repositories (AuthRepository, KeyRepository, TransferRepository) — instance methods with dependency injection via constructor

## Widget Composition

**StatelessWidget for UI building:**
- Reusable UI components with no state: `StepCard`, `UserAvatar`, `BottomSheetHandle`, `CrypButton`
- Located in `lib/presentation/widgets/shared_widgets.dart`

**StatefulWidget for interactive screens:**
- Named as `ScreenName extends StatefulWidget` with private `_ScreenNameState` class
- Use `WidgetsBindingObserver` for lifecycle hooks (e.g., app pause/resume)
- Apply `SecurityLifecycleMixin` for sensitive data handling

**Stream/Provider patterns:**
- `StreamBuilder` for reactive UI updates from Firestore queries
- `ValueNotifier` + `ValueListenableBuilder` for local state (e.g., `SessionManager.stateNotifier`)
- Direct stream subscriptions via `StreamSubscription` for long-lived listeners (e.g., receiver handshake streams)

## Security-Specific Conventions

**Sensitive Data Handling:**
- Register Uint8List buffers with `SecurityLifecycleMixin.registerBuffer()` immediately after allocation
- Explicitly wipe with `fillRange(0, length, 0)` and deregister with `unregisterBuffer()` after use
- Never log key material; use `// ignore: avoid_print` comments sparingly

**Session State Machine:**
- Use `SessionManager` to track receiver session transitions: `open` → `locked` → `decrypting` → `terminated`
- Reactive kill-switch via `EncryptionService.bindSession()` listening to `SessionManager.stateStream`

**Firestore Batch Operations:**
- Atomic writes use `WriteBatch` for multi-document operations (e.g., receiver authorization):
  ```dart
  final batch = FirebaseFirestore.instance.batch();
  batch.set(userDocRef, {'selectedSenderUid': uid});
  batch.set(keyTransferRef, {'status': 'handshake_complete'});
  await batch.commit();
  ```

---

*Convention analysis: 2025-04-19*
