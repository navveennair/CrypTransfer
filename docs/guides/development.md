<!-- generated-by: gsd-doc-writer -->
# Development Guide

This guide covers local development conventions for CrypTransfer: the project's
layered architecture, code style and static analysis, the design system, the
`SecurityLifecycleMixin` pattern for new screens, the local automation scripts,
and the graphify knowledge-graph workflow.

For initial setup and running the app for the first time, see the
[Configuration Overview](../configuration/overview.md) and the root
[README](../../README.md). For the high-level system design, see the
[Architecture Overview](../architecture/overview.md).

## Local Setup

CrypTransfer is a Flutter application (`environment.sdk: ^3.12.0`,
`flutter: '>=3.44.0'` per `pubspec.yaml`) backed by Firebase (Auth, Firestore,
Storage).

1. Install dependencies:

   ```bash
   flutter pub get
   ```

2. Ensure Firebase is configured for your environment — `lib/firebase_options.dart`
   and the platform-specific Firebase config files must be present. See
   [Configuration Overview](../configuration/overview.md) for how to regenerate
   these with `flutterfire configure` if you are pointing at a different
   Firebase project.

3. Run the app on a connected device or emulator:

   ```bash
   flutter run
   ```

4. For release builds, Android signing reads from `android/key.properties`
   (git-ignored). If absent, the build falls back to debug signing so
   `flutter run --release` still works on a fresh machine. See the
   "Android Entry Point" section of the project's `CLAUDE.md` for the exact
   key.properties format.

## Project Layer Conventions

The codebase under `lib/` follows a three-layer architecture. New code should
be placed according to these conventions:

```
lib/
├── core/
│   ├── constants/    ← shared constant values (colors, sizes, strings)
│   ├── errors/       ← AppExceptions and other typed error classes
│   ├── services/     ← cross-cutting services not tied to a single feature
│   └── utils/        ← SecurityLifecycleMixin, SessionManager, SessionState,
│                        biometric_helper, and other shared utilities
├── data/
│   ├── models/       ← plain data classes / Firestore document models
│   ├── repositories/ ← Firestore/Auth/Storage access (auth_repository,
│   │                    key_repository, transfer_repository, ...)
│   └── services/     ← business-logic services (encryption_service,
│                        transfer_service)
├── presentation/
│   ├── admin/        ← admin dashboard screens + widgets
│   ├── auth/         ← sign-in / sign-up screens
│   ├── home/         ← home screen
│   ├── receiver/     ← receiver_screen, receiver_transfer_screen, decrypt_screen
│   ├── sender/       ← sender_screen, transfer_progress_screen
│   ├── session/      ← end_session_screen
│   ├── settings/     ← settings screens
│   ├── vault/        ← key vault / profile init screens
│   └── widgets/       ← shared_widgets.dart (CrypButton, GlassButton, etc.)
└── services/         ← top-level app services (e.g. notification wiring)
```

**Rules of thumb:**

- **`presentation/`** screens and widgets should not call `FirebaseFirestore.instance`
  directly — go through a repository in `data/repositories/`. The
  `silent_guardian.ps1` scanner flags raw `FirebaseFirestore` usage inside
  `presentation/` as a `WARNING` ("Direct Firestore in presentation layer").
- **`data/repositories/`** own all Firestore/Storage/Auth reads and writes for
  a given domain (e.g. `key_repository.dart` owns `handshakes` and
  `neutral_handshakes` collections, `transfer_repository.dart` owns
  `transfers` and `transfer_logs`).
- **`data/services/`** own business logic that doesn't map 1:1 to a Firestore
  collection — `encryption_service.dart` (hybrid RSA/AES crypto +
  `closeReceiverSession()`), `transfer_service.dart` (64 KB chunked file
  reads via `TransferService.resolve()`).
- **`core/utils/`** holds cross-cutting mixins and state machines used by
  multiple screens — `SecurityLifecycleMixin`, `SessionManager`,
  `SessionState` (kept in its own file, `session_state.dart`, specifically to
  avoid a circular import between `SessionManager` and `EncryptionService`).
- Any cryptographic work that runs on user-supplied bytes (key generation,
  AES encryption/decryption) must run inside `compute()`, never directly on
  the main isolate or via `Isolate.run()`.

## Code Style and Static Analysis

CrypTransfer uses the standard Flutter lint set defined in
`analysis_options.yaml`:

```yaml
include: package:flutter_lints/flutter.yaml
```

No project-specific lint rules are currently enabled or disabled beyond the
`flutter_lints` defaults.

Run static analysis before committing:

```bash
flutter analyze
```

The project maintains a **zero-issues** baseline — `flutter analyze` is
expected to report `No issues found`. If you introduce new lints, fix them
rather than adding `// ignore:` comments unless there is a documented reason.

Common lint fixes already applied across the codebase (for reference when
writing similar code):

- Avoid unused positional parameter names in callbacks — use `_` instead of
  `__`/`___` (`unnecessary_underscores`).
- Use `State`'s `mounted` property (not `context.mounted`) inside async
  callbacks before calling `setState` (`use_build_context_synchronously`).
- Prefer top-level functions over locally-defined function variables for
  reusable helpers (`prefer_function_declarations_over_variables`).
- Remove unreferenced widget/constant declarations promptly
  (`unused_element`).

### Tests

Run the test suite with:

```bash
flutter test
```

Tests are organized by domain under `test/`:

- `test/module_tests/` — core module tests (`auth`, `encryption`, `session`,
  `transfer`)
- `test/security/` — security-focused tests (`session_wipe_test.dart`,
  `session_termination_test.dart`, `key_storage_audit_test.dart`,
  `mem_safety_test.dart`, `navigation_guard_test.dart`)
- `test/handshake/`, `test/role_assignment/`, `test/sender/`, `test/vault/`,
  `test/admin/` — feature-specific tests
- `test/mocks/` — shared mocks (`mock_firebase.dart`)

When testing crypto code, prefer calling the low-level top-level functions
(e.g. `runAesGcmEncrypt` / `runAesGcmDecrypt` in
`encryption_service.dart`) directly rather than through `compute()`, since
`compute()` requires the Flutter binding to be initialized.

## Design System

CrypTransfer has a canonical design system under `design-system/cryptransfer/`.
**Before building or modifying any UI**, check for a page-specific override
first:

1. `design-system/pages/[page-name].md` — page-specific rules, if present,
   **override** the master file.
2. `design-system/cryptransfer/MASTER.md` — global source of truth for
   colors, typography, spacing, shadows, and anti-patterns.

Other files in `design-system/cryptransfer/`:

| File | Purpose |
|------|---------|
| `MASTER.md` | Global rules: color palette, typography, spacing tokens, shadow depths, anti-patterns |
| `UI-AUDIT-REPORT.md` | Catalogued UI inconsistencies with severity levels and fixes |
| `UI-CONSISTENCY-MAP.md` | Before/after visual mappings for components (colors, buttons, typography) |
| `QUICK-FIX-GUIDE.md` | Remaining design-system improvements with code diffs |

### Key palette (from `MASTER.md`)

| Role | Hex |
|------|-----|
| Primary | `#F59E0B` |
| Secondary | `#FBBF24` |
| CTA/Accent | `#8B5CF6` |
| Background | `#0F172A` |
| Text | `#F8FAFC` |

All colors should be applied via Material 3's `Theme.of(context).colorScheme`
rather than hardcoded hex values, so that light/dark mode adapts automatically.

**Buttons:** Use `CrypButton` (`lib/presentation/widgets/shared_widgets.dart`)
for all primary/secondary actions. `CrypButton` is a `StatefulWidget` with a
3D press effect (`HapticFeedback.lightImpact()`, scale animation via
`Matrix4.diagonal3Values`) and reacts to `SessionState` (see below) by
overriding its face color and content for `locked`, `decrypting`, and
`terminated` states.

## SecurityLifecycleMixin Pattern for New Screens

Any screen that handles sensitive in-memory data (RSA/AES keys, plaintext
file bytes, decrypted buffers) should apply
`SecurityLifecycleMixin<T>` from `lib/core/utils/security_lifecycle_mixin.dart`.

```dart
class _MyScreenState extends State<MyScreen>
    with SecurityLifecycleMixin<MyScreen> {

  @override
  void initState() {
    super.initState();
    final key = generateKey();
    registerBuffer(key); // will be zeroed automatically on dispose/wipe
  }
}
```

**API surface:**

- `registerBuffer(Uint8List buffer)` — register a sensitive buffer for
  automatic zeroing.
- `unregisterBuffer(Uint8List buffer)` — remove a buffer from the registry
  after it has already been explicitly wiped (identity comparison), to avoid
  a redundant second pass.
- `wipeAll()` — zeroes every registered buffer (`fillRange(0, length, 0)`),
  clears the registry, then calls `onBuffersWiped()` for additional cleanup.
  Safe to call multiple times.
- `onBuffersWiped()` — override this to perform extra state cleanup after a
  wipe. Guard any `setState` with `if (mounted)`, since `dispose()` also
  triggers `wipeAll()`.
- `SecurityLifecycleMixin.isFlagSecureActive()` — static method; queries the
  Kotlin `MainActivity` via the `cryptransfer/security` MethodChannel to
  confirm Android `FLAG_SECURE` is active before any 64 KB chunk read begins.
  Returns `true` on iOS/desktop and on `MissingPluginException` (safe
  fallback for tests/emulators).
- `SecurityLifecycleMixin.requestNativeClear()` — static method; sends a
  best-effort `clearSession` call to Kotlin, which triggers `System.gc()` as
  a heap-release hint. No key material is held natively — all crypto runs in
  Dart `compute()` isolates.

**Currently applied to:** `SenderScreen`, `ReceiverScreen`,
`TransferProgressScreen`, `DownloadConfirmScreen`, `EndSessionScreen`,
`DecryptScreen`.

When adding a new screen that touches keys, plaintext, or decrypted file
bytes:

1. Mix in `SecurityLifecycleMixin<YourScreen>`.
2. Call `registerBuffer()` immediately after creating any `Uint8List` that
   contains sensitive data.
3. If you wipe a buffer early (e.g. right after a `compute()` call returns),
   call `unregisterBuffer()` on it to avoid a redundant zero pass in
   `wipeAll()`.
4. If the screen reads file chunks, call
   `SecurityLifecycleMixin.isFlagSecureActive()` before each 64 KB chunk read
   (see `SenderScreen._encryptFile()` for the existing pattern).
5. Wire any kill-switch / session-state interactions through `SessionManager`
   (`lib/core/utils/session_manager.dart`) rather than ad-hoc state — see the
   "Kill Switch" flow in the [Architecture Overview](../architecture/overview.md).

## Local Automation Scripts

Automation scripts live in `scripts/` and are part of the project's
DevOps & Tooling cluster (build config, CI, and the Guardian reporting
pipeline — not app logic). They are run locally/headlessly, not as part of
the Flutter build.

| Script | Purpose |
|--------|---------|
| `scripts/silent_guardian.ps1` | Headless security scanner. Runs `flutter analyze`, captures recent git changes, and scans `lib/**/*.dart` against the State Scanner Rules (e.g. `SecurityLifecycleMixin` presence, `Isolate.run()` for crypto, raw `FirebaseFirestore` in `presentation/`, `debugPrint` with key data, `closeReceiverSession` wiring). Writes a daily Markdown report to the Obsidian vault. |
| `scripts/update_status.ps1` | Runs `flutter analyze` and checks a set of completion markers against `lib/` (e.g. `SecurityLifecycleMixin` applied to `SenderScreen`/`DecryptScreen`, `compute()` used for RSA decrypt, Face ID re-enabled, legacy `lib/auth`/`lib/home` directories removed). Reports newly-completed and still-open items. |
| `scripts/security_audit_report.dart` | Dart script that generates a structured security audit Markdown report for Obsidian. |
| `scripts/write_obsidian_report.dart` | Dart script that writes a daily summary report to the Obsidian vault. |
| `scripts/launch_guardian.bat` | Windows batch launcher for `silent_guardian.ps1`, intended for Task Scheduler. |
| `scripts/reset_user_audit.js` | Node script that cleans up test data from the `transfers` and audit collections. |

**Background execution policy:**

```
powershell.exe -WindowStyle Hidden -NonInteractive -NoProfile -Command
```

<!-- VERIFY: Obsidian vault output paths (C:\Users\navve\ObsidianVault\CrypTransfer\DailyReports and \Security) and the report_error.log location are local-machine paths and may not apply to other development environments. -->

To run the Guardian scan manually:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\silent_guardian.ps1
```

To check completion status against the project's known checklist:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\update_status.ps1
```

## Knowledge Graph Workflow (graphify)

CrypTransfer maintains a persistent knowledge graph of the codebase at
`graphify-out/graph.json`, generated and queried via the `graphify` skill
(`~/.claude/skills/graphify/SKILL.md`).

- **Before answering codebase questions** about relationships across files
  (e.g. "what calls `closeReceiverSession`?", "which screens use
  `SecurityLifecycleMixin`?"), query the graph rather than re-deriving the
  answer by reading every file:

  ```
  /graphify query "<question>"
  ```

- **After making code changes**, rebuild the graph so it stays in sync:

  ```
  /graphify . --update
  ```

  Code-only changes use AST-based extraction (no LLM call, fast). Changes to
  documentation or images require a full semantic pass.

- **Other exploration commands:** `/graphify path` (find a relationship path
  between two nodes) and `/graphify explain` (explain a node's role and
  connections).

The graph output directory (`graphify-out/`) includes `graph.json`,
`graph.html` (interactive visualization), `GRAPH_REPORT.md`, and supporting
cache/manifest files.
