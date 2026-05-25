# Coding Conventions

**Analysis Date:** 2026-05-25

## Naming Patterns

**Files:**
- `snake_case.dart` for all Dart files
- `*_screen.dart` for full-page screens: `sender_screen.dart`, `receiver_screen.dart`, `receiver_transfer_screen.dart`
- `*_repository.dart` for data access layer: `key_repository.dart`, `transfer_repository.dart`, `auth_repository.dart`, `handshake_repository.dart`, `admin_repository.dart`
- `*_service.dart` for business logic services: `encryption_service.dart`, `transfer_service.dart`, `tofu_service.dart`
- `*_model.dart` for data models: `user_model.dart`, `transfer_model.dart`, `notification_model.dart`
- `*_test.dart` for test files, organized by concern: `session_wipe_test.dart`, `encryption_test.dart`, `session_test.dart`
- `*_mixin.dart` for mixins: `security_lifecycle_mixin.dart`
- `*_helper.dart` for utility helpers: `biometric_helper.dart`
- `shared_widgets.dart` for global reusable components

**Classes:**
- `PascalCase` for all classes: `SessionManager`, `KeyRepository`, `EncryptionService`, `GlassButton`, `AesEncryptResult`
- Private widget state classes use `_PascalCase`: `_SenderScreenState`, `_GlassButtonState`
- Private nested widget classes use `_PascalCase`: `_WaitingForConnectionWidget`, `_ConnectedBadge`
- Exception classes suffix with `Exception`: `AuthException`, `CryptoException`, `NetworkException`, `KeyNotFoundException`

**Functions/Methods:**
- `camelCase` for all function and method names
- Private methods use leading underscore: `_encryptFile()`, `_onHandshakeUpdate()`, `_revertToWaiting()`
- Lifecycle callbacks follow Flutter convention: `initState()`, `dispose()`, `didChangeAppLifecycleState()`
- Getters use `camelCase` without `get` prefix: `bool get _fileSelected => _file != null`
- Event handlers use `_on` + `PascalCase`: `_onHandshakeUpdate()`, `_onSessionStateChanged()`, `_onToggleReady()`, `_onSenderSelected()`
- Setup/teardown methods: `_checkKeyStatus()`, `_loadReadyToReceiveState()`, `_subscribeToFriends()`, `_startHandshakeListener()`
- Top-level isolate functions: descriptive names or `_name` prefix: `_generateRsaKeyPairIsolate()`, `runAesGcmEncrypt()`, `_rsaOaepEncryptIsolate()`

**Variables:**
- `camelCase` for all local and member variables
- Private fields use leading underscore: `_receiverId`, `_encryptedBytes`, `_sessionLocked`, `_sessionManager`
- Public fields are rare; use property accessors instead
- Boolean flags describe state with `is`/`has` prefix: `_isReadyToReceive`, `_isTogglingReady`, `_hasPrivateKey`, `_hasPublicKey`
- Collection/stream fields describe contents: `_connectedFriends`, `_encryptedBytes`, `_handshakeSub`, `_transferStream`
- Timer and controller fields: `_readinessTimer`, `_progressCtrl`
- Constants use `camelCase`: `const userId = 'test_receiver_uid'`, `const senderId = 'sender-uid'`

**Types/Generics:**
- `PascalCase`: `Uint8List`, `QuerySnapshot<Map<String, dynamic>>`, `StreamController<SessionState>`
- Type parameters descriptive: `QuerySnapshot<Map<String, dynamic>>`

## Code Style

**Formatting:**
- **Tool:** `flutter format` (Dart's built-in formatter) via `dart format .`
- **Line length:** Soft 100 chars, hard 120 chars (enforced by Flutter analyzer)
- **Indentation:** 2 spaces (Dart standard)
- **Trailing commas:** Used in lists/maps to enable formatter wrapping
- **Brackets:** Opening brackets on same line; closing brackets on new line for multi-line constructs

**Example formatting:**
```dart
// Single line
return UserModel(uid: doc.id, username: '', email: '');

// Multi-line (trailing commas enable auto-wrapping)
return UserModel(
  uid: doc.id,
  username: data['username'] as String? ?? '',
  email: data['email'] as String? ?? '',
  publicKey: data['publicKey'] as String?,
);
```

**Linting:**
- **Tool:** `flutter_lints` (6.0.0) - enforces Effective Dart + Flutter recommendations
- **Config:** `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml`
- **Enforcement:** `flutter analyze` passes with zero issues (as of 2026-05-15)
- **Key rules enforced:**
  - No bare `print()` statements in production code (use structured logging or `debugPrint()`)
  - No `unnecessary_underscores` (e.g., `__var` replaced with `_var`)
  - No deprecated Material properties (e.g., `Switch.activeColor` → `Switch.activeThumbColor`)
  - Type annotations required for public APIs
  - Prefer `const` constructors where possible

**Recent lint fixes:**
- `lib/presentation/auth/splash_screen.dart` - removed `__`/`___` underscores
- `lib/presentation/receiver/receiver_screen.dart` - replaced deprecated `Switch.activeColor` with `Switch.activeThumbColor`

## Import Organization

**Order:**
1. `dart:` imports (e.g., `dart:async`, `dart:convert`, `dart:typed_data`, `dart:math`)
2. `package:flutter/` imports (e.g., `package:flutter/material.dart`, `package:flutter/foundation.dart`)
3. Third-party package imports (e.g., `package:cloud_firestore/cloud_firestore.dart`, `package:pointycastle/export.dart`)
4. Project imports (relative, organized by layer)
   - Core/utils first: `'../../core/utils/session_manager.dart'`
   - Constants: `'../../core/constants/firebase_constants.dart'`
   - Errors: `'../../core/errors/app_exceptions.dart'`
   - Models: `'../../data/models/user_model.dart'`
   - Repositories: `'../../data/repositories/key_repository.dart'`
   - Services: `'../../data/services/encryption_service.dart'`
   - Presentation/widgets: `'../widgets/shared_widgets.dart'`, `'../home/home_screen.dart'`
5. Exports (if any) at the end: `export 'session_state.dart';`

**Example:**
```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pointycastle/export.dart' hide State, Padding;

import '../../app_theme.dart';
import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/utils/session_manager.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/key_repository.dart';
import '../../data/services/encryption_service.dart';
import '../widgets/shared_widgets.dart';

export 'session_state.dart';
```

**Path Aliases:**
- Not used; project uses relative imports exclusively
- Import paths clearly show layer separation: `'../../'` shows deep nesting, `'../'` shows sibling directory

## Error Handling

**Pattern:**
- Use typed exception hierarchy from `lib/core/errors/app_exceptions.dart`
- All exceptions inherit from `AppException` base class
- Specific subtypes for different failure domains:
  - `AuthException` — Firebase Auth failures
  - `TransferException` — transfer document operations
  - `CryptoException` — RSA/AES encryption/decryption
  - `NetworkException` — Firestore/Storage network failures
  - `KeyNotFoundException` — missing RSA private/public keys

**Catching Firebase errors:**
```dart
try {
  await _db.collection(...).get();
} on FirebaseException catch (e) {
  throw NetworkException('Operation failed: ${e.message ?? e.code}');
}
```

**Catching crypto failures:**
```dart
try {
  return cipher.process(data);
} catch (e) {
  throw CryptoException('RSA encryption failed: $e');
}
```

**UI error display:**
```dart
try {
  await _operation();
} catch (e) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
  }
}
```

**No silent failures:**
- Empty `catch (_) {}` blocks permitted only when:
  1. Error is expected and non-critical (e.g., `_friendsSub?.listen(..., onError: (_) {},)`)
  2. Documented with inline comment explaining why silence is safe

## Logging

**Framework:** `debugPrint()` for debug output; `print()` suppressed in production via linter

**Patterns:**
- Security-sensitive data NEVER logged (RSA keys, plaintexts, UIDs in production code)
- Progress and state transitions logged: `debugPrint('Encryption progress: 50%')`
- Test assertions logged with context: `print('✅ TC-WIPE-001 PASSED: Public key deleted')`
- Error context logged: `throw CryptoException('RSA decryption failed: wrong key')`

**Example:**
```dart
// Good: state transition in debug mode
if (kDebugMode) debugPrint('SessionManager state transition: open → locked');

// Good: progress updates
debugPrint('Chunk encrypted: ${(_encryptionProgress * 100).toStringAsFixed(1)}%');

// Good: error context
throw CryptoException('RSA decryption failed: $e');

// BAD: never log key material
// debugPrint('RSA private key: $privateKeyData'); ❌
// print('AES key bytes: $keyData'); ❌
```

## Comments

**When to Comment:**
- Complex algorithms (e.g., GCM authentication, RSA-OAEP)
- Security/safety-critical sections (e.g., `fillRange(0, ...)` for memory wipe)
- Non-obvious design decisions (e.g., why `compute()` over `Isolate.run()`, why deferred sender selection)
- Workarounds for bugs or platform limitations
- Referenced tickets/issue tracking (e.g., `// CR-01: suppress cold-start empty-snapshot eject`)

**JSDoc/Doc Comments (Dart Doc):**
- Used for public APIs and methods
- Three-slash `///` comments for public symbols
- Two-slash `//` comments for private methods and temporary notes
- Markdown formatting: **bold**, `code`, bullet lists, cross-references with `[ClassName]`

**Example:**
```dart
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

// CR-01: skip the first empty snapshot (Firestore stream fires synchronously
// on subscription before any data has loaded — treat it as settled and return).
if (!_streamSettled) {
  _streamSettled = true;
  return;
}
```

**Section dividers:**
- Use `// ─── Heading ──────────────────────` separator lines for visual section breaks
- Improves code readability, especially in large service classes
- Example from `encryption_service.dart`:
  ```dart
  // ─── Secure random ──────────────────────────────────────────────────
  static Uint8List secureRandomBytes(int length) { ... }
  
  // ─── AES-256-GCM ────────────────────────────────────────────────────
  static Future<AesEncryptResult> encryptAesGcm(...) { ... }
  ```

## Function Design

**Size:** 
- Aim for 20-30 lines per function
- Longer functions (50+ lines) extract helper methods
- Async functions that chain multiple operations use `await` sequentially for clarity
- Screens with 200+ lines break build into `_build*` helper methods

**Parameters:**
- Positional required parameters first
- Named optional parameters with sensible defaults: `{FirebaseFirestore? db, FirebaseAuth? auth}`
- Avoid boolean parameters for flags; use enums or named booleans for clarity
- Pass objects with context instead of loose parameters: `selectSender(String uid, String username)` not `selectSender(uid)`

**Return Values:**
- Explicit return types on all public methods (Dart analyzer enforces this)
- Nullable types indicated with `?`: `String?`, `Uint8List?`, `UserModel?`
- Use `Future<T>` for async operations, never bare `Future`
- Consistent nullable vs. non-nullable:
  ```dart
  // Good: consistent nullable return
  Future<String?> getPublicKey() async {
    final doc = await _db.collection(...).doc(...).get();
    return doc.data()?['publicKey'] as String?;
  }
  ```

## Module Design

**Exports:**
- Barrel files group related exports at top level
- Example: `session_manager.dart` exports `SessionState` for single-import access
- Enables: `import '...session_manager.dart'` gets both `SessionManager` and `SessionState`

**Class organization:**
- One public class per file (rare exceptions for tightly-coupled types)
- Private helpers and top-level functions in the same file
- Top-level isolate functions required for `compute()` — must be top-level, not methods

**Example (from `encryption_service.dart`):**
```dart
// Top-level isolate function (required for compute())
Uint8List runAesGcmEncrypt(List<Uint8List> args) { ... }
Uint8List runAesGcmDecrypt(List<Uint8List> args) { ... }

// Result type
class AesEncryptResult {
  final Uint8List ciphertext;
  final Uint8List key;
  final Uint8List iv;
  const AesEncryptResult({...});
}

// Main service class
class EncryptionService {
  const EncryptionService._();
  
  // Public static methods
  static Uint8List secureRandomBytes(int length) { ... }
  static Future<AesEncryptResult> encryptAesGcm(...) { ... }
  static Future<Uint8List> decryptAesGcm(...) { ... }
  // ...
}
```

**State management:**
- Private fields with leading underscore
- No external direct access to mutable state
- Expose state via getters or streams: `Stream<SessionState> get stateStream => ...`
- Use `ValueNotifier` for reactive UI updates (subscribed via `ValueListenableBuilder`)

**Example (from `session_manager.dart`):**
```dart
class SessionManager {
  // Private state
  final ValueNotifier<SessionState> stateNotifier = 
      ValueNotifier(SessionState.open);
  
  // Public accessor
  SessionState get state => stateNotifier.value;
  
  // Reactive stream for complex subscribers
  Stream<SessionState> get stateStream => _stateStreamController.stream;
  
  // Controlled mutation
  void _set(SessionState next) {
    if (stateNotifier.value != next) {
      stateNotifier.value = next;
      _stateStreamController.add(next);
    }
  }
}
```

## Mixins and Helpers

**Mixins:**
- Used for cross-cutting concerns shared across multiple screens
- Example: `SecurityLifecycleMixin<T extends StatefulWidget>` applied to 6+ screens for uniform memory wipe + lifecycle handling
- Declared with `mixin` keyword, applied via `with` in class definition
- Location: `lib/core/utils/security_lifecycle_mixin.dart`
- Provides: `registerBuffer()`, `unregisterBuffer()`, `wipeAll()` for memory safety

**Helpers:**
- Prefer static utility methods in services (e.g., `EncryptionService.secureRandomBytes()`)
- Use helper classes for grouped utilities (e.g., `BiometricHelper` for Face ID operations)
- Avoid free-floating utility functions; keep them in dedicated service/helper classes
- Example: `BiometricHelper.isBiometricAvailable()`, `BiometricHelper.authenticate()`

## Widget Patterns

**StatelessWidget vs. StatefulWidget:**
- `StatelessWidget` for pure presentation (no state updates mid-lifecycle): `StepCard`, `UserAvatar`, `GlassContainer`
- `StatefulWidget` for interactive components or those needing lifecycle: `GlassButton`, `_SearchResultTile`, screens with `WidgetsBindingObserver`

**Widget composition:**
- Break large screens into private helper methods returning Widgets
- Prefix with `_build`: `_buildStep1Content()`, `_buildConnectionStatus()`, `_buildReadyToggle()`
- Each helper focuses on one UI region; keep `build()` scannable (~30-50 lines)

**Example (from `sender_screen.dart`):**
```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(...),
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_receiverSelected) _buildConnectedBadge(),
            _buildStep1(),
            _buildStep2(),
            _buildStep3(),
            _buildStep4(),
          ],
        ),
      ),
    ),
  );
}

Widget _buildConnectedBadge() {
  return GlassContainer(
    child: Row(...),
  );
}

Widget _buildStep2() {
  return StepCard(
    step: 2,
    title: 'Select File',
    done: _fileSelected,
    child: _step2Content(),
  );
}
```

## Async Patterns

**Futures and Streams:**
- Use `async`/`await` for sequential async operations
- Use `Stream` + `StreamSubscription` for long-lived subscriptions (e.g., Firestore listeners)
- Store subscriptions in fields and **cancel in `dispose()`** — critical for memory safety
- Use `ValueNotifier` + listener pattern for local state changes

**Sequential async:**
```dart
Future<void> _loadData() async {
  try {
    final user = await _db.collection('users').doc(uid).get();
    final profile = await _db.collection('profiles').doc(uid).get();
    setState(() {
      _user = user.data();
      _profile = profile.data();
    });
  } catch (e) {
    _showError('Load failed: $e');
  }
}
```

**Long-lived listener — always cancel in dispose:**
```dart
void initState() {
  super.initState();
  _sub = _db.collection('transfers')
      .where('receiverId', isEqualTo: _uid)
      .snapshots()
      .listen((snap) {
    setState(() => _transfers = snap.docs);
  }, onError: (_) {});  // Silently ignore Firestore errors
}

void dispose() {
  _sub?.cancel();  // CRITICAL: prevent memory leak
  super.dispose();
}
```

**Stream-based state (ValueNotifier):**
```dart
class SessionManager {
  final ValueNotifier<SessionState> stateNotifier = 
      ValueNotifier(SessionState.open);
  
  Stream<SessionState> get stateStream => _stateStreamController.stream;
}

// In widget
void initState() {
  _sessionManager.stateNotifier.addListener(_onSessionStateChanged);
}

void dispose() {
  _sessionManager.stateNotifier.removeListener(_onSessionStateChanged);
  super.dispose();
}
```

## Constants and Configuration

**Location:**
- App-wide constants in `lib/core/constants/firebase_constants.dart`
- Theme constants in `lib/app_theme.dart` (colors, fonts, glass blur effect)
- Magic numbers extracted to named constants: `const kChunkSize = 64 * 1024` in `transfer_service.dart`
- Firestore collection/field names stored in `FirebaseConstants` class

**Example (from `firebase_constants.dart`):**
```dart
class FirebaseConstants {
  static const String users = 'users';
  static const String transfers = 'transfers';
  static const String rsa_key_transfers = 'rsa_key_transfers';
  static const String handshakes = 'handshakes';
  static const String friendships = 'friendships';
  static const String notifications = 'notifications';
  static const String transferLogs = 'transfers_log';
}
```

**Configuration files:**
- `pubspec.yaml` — dependencies, Flutter config, asset references
- `analysis_options.yaml` — linter rules, analysis config
- `android/app/build.gradle.kts` — Android SDK, signing, R8 minification
- `android/key.properties` (git-ignored) — release signing credentials
- `.env` files (git-ignored) — Firebase project IDs, secrets

## Security-Specific Patterns

**Memory-sensitive operations:**
- Always register `Uint8List` buffers with `SecurityLifecycleMixin.registerBuffer()` immediately after allocation
- Explicitly wipe with `fillRange(0, length, 0)` and deregister with `unregisterBuffer()` after use
- Lifecycle observer `didChangeAppLifecycleState` triggers `SessionManager.wipeSession()` on app pause/detach

**Firestore batch operations:**
- Atomic writes use `WriteBatch` for multi-document transactions
- Example: receiver authorization writes user doc + handshake doc in one commit
  ```dart
  final batch = _db.batch();
  batch.set(userDocRef, {'selectedSenderUid': uid});
  batch.set(handshakeRef, {'status': 'handshake_complete'});
  await batch.commit();
  ```

**Isolate-based crypto:**
- Heavy computations (`compute()`) delegate to background isolate
- Top-level isolate functions required (not instance methods)
- Example: `_generateRsaKeyPairIsolate` for 2048-bit RSA generation

---

*Convention analysis: 2026-05-25*
