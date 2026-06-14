# Coding Conventions
_Last updated: 2026-06-15_

## Code Style

**Linting:**
- `package:flutter_lints/flutter.yaml` via `analysis_options.yaml`
- `flutter analyze` must pass with **No issues found** before committing
- Per-line suppression with `// ignore: rule_name`; per-file with `// ignore_for_file: rule_name`
- Key enforced rules encountered in practice:
  - `unnecessary_underscores` — use `_` not `__`/`___` in callbacks (e.g. `PageRouteBuilder`, `AnimatedBuilder`)
  - `non_constant_identifier_names` — private widget helpers use lowerCamelCase (e.g. `_sectionLabel`, not `_SectionLabel`)
  - `prefer_function_declarations_over_variables` — top-level helpers extracted as named functions, not variables
  - `use_build_context_synchronously` — always check `mounted` (State's `mounted`, not `context.mounted`) before using context after an `await`
  - `unused_element` — remove unreferenced private constants immediately

**Formatting:**
- Standard Dart formatter (`dart format`) — no custom `.prettierrc` or Biome config
- Double quotes for strings (Dart default; no `prefer_single_quotes` override)
- 80-character soft line limit (Dart default)

## Naming Conventions

**Files:**
- `snake_case.dart` for all Dart files (e.g. `sender_screen.dart`, `session_manager.dart`)
- Screen files end in `_screen.dart` (e.g. `receiver_screen.dart`)
- Repository files end in `_repository.dart` (e.g. `key_repository.dart`)
- Service files end in `_service.dart` (e.g. `encryption_service.dart`)
- Model files end in `_model.dart` (e.g. `transfer_model.dart`)
- Mixin files end in `_mixin.dart` (e.g. `security_lifecycle_mixin.dart`)
- Test files mirror source path and end in `_test.dart`

**Classes:**
- `PascalCase` for all class names (e.g. `TransferRepository`, `SessionManager`)
- Private State classes prefixed with `_` (e.g. `_SenderScreenState`)
- Abstract constant holders use `abstract class` (e.g. `abstract class FirebaseConstants`)

**Functions and Methods:**
- `camelCase` for public methods (e.g. `selectSender`, `wipeSession`, `uploadAndCreate`)
- `_camelCase` for private methods (e.g. `_encryptFile`, `_onToggleReady`, `_set`)
- Private helper widgets defined as functions use `lowerCamelCase` (e.g. `_sectionLabel`)
- Getter computed properties preferred for derived state (e.g. `bool get _fileEncrypted => _encryptedBytes != null`)
- Isolate-safe top-level functions named descriptively (e.g. `runAesGcmEncrypt`, `_rsaOaepEncryptIsolate`)

**Variables:**
- `camelCase` for locals and fields (e.g. `activeSenderUid`, `encryptedAESKey`)
- `SCREAMING_SNAKE_CASE` for constants: `static const String privateKeyStorageKey = 'rsa_private_key'`
- Nullable fields declared with `?` (e.g. `String? _receiverId`, `StreamSubscription? _handshakeSub`)
- `late final` used for streams initialized in `initState` (e.g. `late final Stream<QuerySnapshot> _recentTransfersStream`)

**Private prefix rules:**
- All `State` fields are private (`_`)
- All repository/service fields on State are private (`_connService`, `_transferRepo`)
- Constructor-injected dependencies on repositories are named with leading `_` (e.g. `_db`, `_auth`, `_secure`)

**Enums:**
- `PascalCase` for enum type, `camelCase` for values (e.g. `enum TransferStatus { pending, received, completed }`)

## Patterns Used

**Repository Pattern:**
- All Firestore and Storage I/O is encapsulated in `lib/data/repositories/*.dart`
- Repositories accept optional injected dependencies for testability:
  ```dart
  KeyRepository({FirebaseFirestore? db, FirebaseAuth? auth, FlutterSecureStorage? secure})
      : _db = db ?? FirebaseFirestore.instance, ...
  ```
- Screens instantiate repositories directly via `final _connService = KeyRepository()` (no DI container)

**Mixin Pattern (SecurityLifecycleMixin):**
- Applied to every screen that handles sensitive data: `with SecurityLifecycleMixin<MyScreen>`
- Provides `registerBuffer`, `unregisterBuffer`, `wipeAll`, `onBuffersWiped`, and `isFlagSecureActive`
- Applied to: `SenderScreen`, `ReceiverScreen`, `TransferProgressScreen`, `DownloadConfirmScreen`, `EndSessionScreen`, `DecryptScreen`
- Located at: `lib/core/utils/security_lifecycle_mixin.dart`

**ValueNotifier + Stream dual-channel state:**
- `SessionManager` exposes both a `ValueNotifier<SessionState> stateNotifier` (for UI via `ValueListenableBuilder`) and a `Stream<SessionState> stateStream` (for reactive service binding via `EncryptionService.bindSession`)
- Located at: `lib/core/utils/session_manager.dart`

**Abstract Constants Class:**
- All Firestore collection names, Storage paths, and secure storage keys live in `lib/core/constants/firebase_constants.dart`
- Never hardcode collection name strings inline — always reference `FirebaseConstants.transfers` etc.

**Factory Constructors for Models:**
- `fromDoc(DocumentSnapshot<Map<String, dynamic>>)` factory constructor on all models
- `toCreateMap()` method for Firestore writes (returns `Map<String, dynamic>`)
- Example: `lib/data/models/transfer_model.dart`

**Glassmorphic Widget System:**
- `CrypButton` (`lib/presentation/widgets/shared_widgets.dart`) is the single button widget; never use raw `ElevatedButton`/`TextButton`/`GlassButton`
- `CrypButton` accepts `sessionState` param to drive visual feedback (amber/lock, spinner, red/block)
- `StatefulWidget` buttons with `_isPressed`, `HapticFeedback.lightImpact()`, and `AnimatedContainer` scale

**Section dividers:**
- Horizontal rule comments used to separate logical sections within files:
  ```dart
  // ─── User search ──────────────────────────────────────────────────────────
  ```

## Error Handling

**Typed Exception Hierarchy:**
- All app errors are typed subclasses of `AppException` in `lib/core/errors/app_exceptions.dart`
- Types: `AuthException`, `TransferException`, `CryptoException`, `NetworkException`, `KeyNotFoundException`, `RoleConflictException`
- Repository methods catch `FirebaseException` and wrap it:
  ```dart
  on FirebaseException catch (e) {
    throw NetworkException('User search failed: ${e.message ?? e.code}');
  }
  ```

**Surface at presentation layer:**
- Screens catch typed exceptions and call SnackBar helpers:
  ```dart
  } catch (e) {
    _showErrorSnackBar('Error: $e');
  }
  ```
- Consolidated SnackBar helpers reduce boilerplate (e.g. `_showErrorSnackBar`, `_showInfoSnackBar` in `home_screen.dart`)
- Always check `mounted` before showing SnackBar: `if (!mounted) return;`

**Idempotent guard pattern:**
- Storage and cleanup operations guard for "object-not-found":
  ```dart
  on FirebaseException catch (e) {
    if (e.code != 'object-not-found') rethrow;
  }
  ```

**Crypto errors:**
- `EncryptionService` catches low-level pointycastle errors and re-throws as `CryptoException`
- `EncryptionService.rsaDecrypt` throws `CryptoException` on wrong-key decryption attempt

**Silent swallowing (limited use):**
- `SecurityLifecycleMixin.isFlagSecureActive()` swallows `MissingPluginException` and returns `true` (safe fallback)
- `SecurityLifecycleMixin.requestNativeClear()` swallows all errors silently (best-effort GC hint only)
- `wipeAll()` wraps each `fillRange` in a try-catch to swallow read-only buffer edge cases

## Async Patterns

**`async*` / `yield` for upload streams:**
- `TransferRepository.uploadAndCreate()` uses `async*` generator to yield upload progress (0.0 → 1.0):
  ```dart
  Stream<double> uploadAndCreate({...}) async* {
    await for (final snapshot in task.snapshotEvents) { yield ...; }
    yield 1.0;
  }
  ```

**`compute()` for heavy crypto:**
- All RSA key generation and AES-GCM encrypt/decrypt runs in `compute()` isolates, not main isolate
- Top-level functions required for `compute()` (cannot be instance methods)
- Example in `lib/data/services/encryption_service.dart`: `compute(runAesGcmEncrypt, [plaintext, key, iv])`

**`StreamController.broadcast()` for multi-listener streams:**
- Used in `SessionManager._stateStreamController` (for `EncryptionService.bindSession`)
- Used in `FindFriendsScreen` per-tile `streamHandshakeWithUser` merging two doc streams

**`StreamSubscription` lifecycle:**
- All subscriptions stored as nullable fields (e.g. `StreamSubscription? _handshakeSub`)
- Cancelled in `dispose()` via `?.cancel()`
- Streams that must survive rebuilds are initialized in `initState` and stored as `late final Stream` fields to prevent double-subscription

**`StreamBuilder` for reactive UI:**
- Used in `ReceiverScreen` for live transfer detection (references stable `_transferStream` field, not inline stream creation)
- Used in `FindFriendsScreen._SearchResultTile` for per-tile connection status

**`ValueNotifier` + `ValueListenableBuilder`:**
- `SessionManager.stateNotifier` drives `CrypButton` session state visuals reactively without full rebuilds

**`async/await` with `mounted` guard:**
- All async callbacks check `if (!mounted) return;` before calling `setState` or `context.*`
- Prefer State's `mounted` property (not `context.mounted`) to avoid `use_build_context_synchronously` lints

**`Future.wait` for parallel Firestore reads:**
- Used in `KeyRepository.sendConnectionRequest()` to read both user docs simultaneously

## Comments & Documentation

**Triple-slash doc comments (`///`) on:**
- All public class declarations
- All public methods in repositories and services
- Mixin members with non-obvious contracts
- Example:
  ```dart
  /// Atomically marks [senderUid] as the session-authorized sender.
  ///
  /// A single [WriteBatch] commits two writes together:
  /// 1. `users/{receiverUid}.selectedSenderUid = senderUid`
  /// 2. `handshakes` — upserts the receiver's RSA public key...
  ```

**Inline comments for non-obvious logic:**
- Security rationale documented inline (e.g. `// FLAG_SECURE set — blocks task-switcher thumbnails`)
- `// ignore: rule_name` always accompanied by a comment explaining why

**File-level block comments for test files:**
- Test ranges noted at top: `// ── Transfer Tests (TC022–TC030) ──`
- Test case IDs in every test name: `'TC031 - Session cancelled when sender deletes transfer'`

**Section dividers in large files:**
- `// ─── Section name ────────────────────────────────────────────────────────` pattern used to separate logical sections inside large classes
- Consistent use in `key_repository.dart`, `encryption_service.dart`, `session_manager.dart`

**No `debugPrint` of key material:**
- `debugPrint` and `print` are only used in test files for pass/fail output, never in production lib code for sensitive data
- `avoid_print` lint rule is available but not enabled project-wide (commented out in `analysis_options.yaml`)
