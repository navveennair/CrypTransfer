# Phase 8: applicationId Rename — Pattern Map

**Mapped:** 2026-05-29
**Files analyzed:** 7 modified + 1 physical move + 1 tree deletion + 1 optional new test
**Analogs found:** 7 self-analogs (rename in place) / 1 sibling-analog (Wave 0 test)

> **Phase nature:** This is a coordinated mechanical RENAME, not a new-feature build. For every touched file, the "analog" is the file's own current on-disk state — the pattern to copy from is the BEFORE block; the pattern to write is the AFTER block. Both are surfaced verbatim below from authoritative reads. The single exception is the optional Wave 0 test, which uses `test/security/session_wipe_test.dart` as its scaffolding template.

## File Classification

| File | Role | Data Flow | Closest Analog | Match Quality |
|------|------|-----------|----------------|---------------|
| `android/app/build.gradle.kts` | config (Gradle DSL) | build-time | **self** (lines 22, 43) | self-rename |
| `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt` → `.../com/navveennair/cryptransfer/MainActivity.kt` | native bridge (Kotlin entry) | request-response (MethodChannel) | **self** (lines 1, 20, 25, 33, 34) | self-rename + physical move |
| `lib/core/utils/security_lifecycle_mixin.dart` | utility (mixin) | request-response (MethodChannel consumer) | **self** (line 24) | self-rename |
| `lib/presentation/receiver/decrypt_screen.dart` | screen (StatefulWidget) | request-response (MethodChannel consumer) | **self** (line 52) | self-rename |
| `lib/firebase_options.dart` | config (generated) | static config | **self** (lines 67, 76) | self-rename |
| `android/app/google-services.json` | config (Firebase plugin input) | build-time | **self** (lines 12, 20, 45) | wholesale replace (Console download) |
| `android/app/proguard-rules.pro` | config (R8 keep rules) | build-time | **self** | verify-only (no edit) |
| `android/app/src/main/AndroidManifest.xml` | config (manifest) | build-time | **self** (line 40) | verify-only (Gradle placeholder auto-resolves) |
| `android/app/src/main/kotlin/com/example/` | directory tree | — | — | DELETE wholesale |
| `test/android/method_channel_naming_test.dart` (OPTIONAL) | test (unit) | string-equality assertion | `test/security/session_wipe_test.dart` (scaffolding only) + `test/security/mem_safety_test.dart` (pure-logic style) | sibling-analog |

## Pattern Assignments

### `android/app/build.gradle.kts` (config, build-time)

**Analog:** self. File is small (75 lines); preserve everything except lines 22 and 43.

**BEFORE — lines 21-23** (verbatim from `android/app/build.gradle.kts`):
```kotlin
android {
    namespace = "com.example.cryptransfer"
    compileSdk = flutter.compileSdkVersion
```

**AFTER — lines 21-23:**
```kotlin
android {
    namespace = "com.navveennair.cryptransfer"
    compileSdk = flutter.compileSdkVersion
```

**BEFORE — lines 42-44** (verbatim):
```kotlin
    defaultConfig {
        applicationId = "com.example.cryptransfer"
        minSdk = flutter.minSdkVersion
```

**AFTER — lines 42-44:**
```kotlin
    defaultConfig {
        applicationId = "com.navveennair.cryptransfer"
        minSdk = flutter.minSdkVersion
```

**Untouched anchors** (DO NOT EDIT — keep verbatim):
- `signingConfigs` block (lines 31-40) — reads `android/key.properties`, has no package reference
- `buildTypes.release` block (lines 50-64) — R8 minification + signing fallback, no package reference
- `flutter { source = "../.." }` (lines 67-69)
- `kotlin { compilerOptions { jvmTarget = JVM_17 } }` (lines 71-75)

---

### `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt` → `.../com/navveennair/cryptransfer/MainActivity.kt` (native bridge, request-response)

**Analog:** self. Physical move via `git mv` + 5 in-file edits. File is 122 lines; only lines 1, 20, 25, 33, 34 change.

**Physical move command** (mandatory `git mv` to preserve history):
```
git mv android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt \
       android/app/src/main/kotlin/com/navveennair/cryptransfer/MainActivity.kt
```

**BEFORE — line 1** (verbatim from `MainActivity.kt`):
```kotlin
package com.example.cryptransfer
```

**AFTER — line 1:**
```kotlin
package com.navveennair.cryptransfer
```

**BEFORE — KDoc lines 15-30** (verbatim):
```kotlin
/**
 * CrypTransfer Android entry point.
 *
 * Native–Dart security bridge
 * ─────────────────────────────────────────────────────────────────────────────
 * Channel 1 — "com.example.cryptransfer/security"
 *   isFlagSecureActive  → returns (flags & FLAG_SECURE) != 0
 *   clearSession        → System.gc() hint (no key bytes held natively)
 *   Consumed by: SecurityLifecycleMixin  (lib/core/utils/security_lifecycle_mixin.dart)
 *
 * Channel 2 — "com.example.cryptransfer/file"
 *   saveToDownloads(fileName, bytes) → saves to public Downloads folder
 *     Android 10+ : MediaStore.Downloads (no WRITE_EXTERNAL_STORAGE needed)
 *     Android <10 : direct FileOutputStream (needs WRITE_EXTERNAL_STORAGE)
 *   Consumed by: DecryptScreen._saveAndWipe()  (lib/presentation/receiver/decrypt_screen.dart)
 */
```

**AFTER — KDoc lines 15-30 (lines 20 and 25 only change):**
```kotlin
/**
 * CrypTransfer Android entry point.
 *
 * Native–Dart security bridge
 * ─────────────────────────────────────────────────────────────────────────────
 * Channel 1 — "cryptransfer/security"
 *   isFlagSecureActive  → returns (flags & FLAG_SECURE) != 0
 *   clearSession        → System.gc() hint (no key bytes held natively)
 *   Consumed by: SecurityLifecycleMixin  (lib/core/utils/security_lifecycle_mixin.dart)
 *
 * Channel 2 — "cryptransfer/file"
 *   saveToDownloads(fileName, bytes) → saves to public Downloads folder
 *     Android 10+ : MediaStore.Downloads (no WRITE_EXTERNAL_STORAGE needed)
 *     Android <10 : direct FileOutputStream (needs WRITE_EXTERNAL_STORAGE)
 *   Consumed by: DecryptScreen._saveAndWipe()  (lib/presentation/receiver/decrypt_screen.dart)
 */
```

**BEFORE — lines 31-34** (verbatim — channel constants):
```kotlin
class MainActivity : FlutterFragmentActivity() {

    private val securityChannel = "com.example.cryptransfer/security"
    private val fileChannel     = "com.example.cryptransfer/file"
```

**AFTER — lines 31-34:**
```kotlin
class MainActivity : FlutterFragmentActivity() {

    private val securityChannel = "cryptransfer/security"
    private val fileChannel     = "cryptransfer/file"
```

**Untouched anchors** (DO NOT EDIT — keep verbatim):
- Imports (lines 1-13) except line 1 package declaration
- `onCreate` block (lines 36-41) — sets FLAG_SECURE; no package reference
- `configureFlutterEngine` (lines 43-87) — uses `securityChannel`/`fileChannel` *constants*, NOT the literal strings, so the rename of the constants automatically propagates here
- `saveToDownloads` helper (lines 89-120) — pure Android API; no package reference

---

### `lib/core/utils/security_lifecycle_mixin.dart` (utility, request-response consumer)

**Analog:** self. File is 109 lines; only line 24 changes.

**BEFORE — lines 21-24** (verbatim from `security_lifecycle_mixin.dart`):
```dart
  // ─── Kotlin sync: FLAG_SECURE pre-flight check ────────────────────────────

  static final _securityChannel =
      const MethodChannel('com.example.cryptransfer/security');
```

**AFTER — lines 21-24:**
```dart
  // ─── Kotlin sync: FLAG_SECURE pre-flight check ────────────────────────────

  static final _securityChannel =
      const MethodChannel('cryptransfer/security');
```

**Critical invariant:** The string on line 24 MUST byte-equal the Kotlin `securityChannel` constant at `MainActivity.kt:33` post-rename. No leading slash, no trailing whitespace, lowercase only.

**Untouched anchors** (DO NOT EDIT — keep verbatim):
- `requestNativeClear` (lines 32-36) — uses the `_securityChannel` field, not the literal; rename propagates
- `isFlagSecureActive` (lines 50-59) — uses the `_securityChannel` field; rename propagates. **Note:** lines 54-58 swallow `MissingPluginException` and return `true` — this means a typo on line 24 will silently fall back rather than crash. The smoke-test step in D-06 (task-switcher screenshot test) is the ONLY runtime catch.
- Buffer registry (lines 61-101) — no channel reference

---

### `lib/presentation/receiver/decrypt_screen.dart` (screen, request-response consumer)

**Analog:** self. File is 600+ lines; only line 52 changes.

**BEFORE — lines 50-52** (verbatim from `decrypt_screen.dart`):
```dart
class _DecryptScreenState extends State<DecryptScreen>
    with SecurityLifecycleMixin<DecryptScreen> {
  static const _fileChannel = MethodChannel('com.example.cryptransfer/file');
```

**AFTER — lines 50-52:**
```dart
class _DecryptScreenState extends State<DecryptScreen>
    with SecurityLifecycleMixin<DecryptScreen> {
  static const _fileChannel = MethodChannel('cryptransfer/file');
```

**Critical invariant:** The string on line 52 MUST byte-equal the Kotlin `fileChannel` constant at `MainActivity.kt:34` post-rename. No silent fallback exists on this channel — a typo surfaces as a `MissingPluginException` SnackBar when the user taps "Save & Continue".

**Untouched anchors** (DO NOT EDIT — keep verbatim):
- Imports (lines 1-22) — no package reference
- `_decryptAesKeyIsolate` top-level helper (lines 26-33) — pure crypto, no package reference
- All state fields beyond line 52 (lines 54-72) — no package reference
- Downstream consumer at the existing `_saveAndWipe()` site uses `_fileChannel.invokeMethod('saveToDownloads', ...)` — propagates via the field rename

---

### `lib/firebase_options.dart` (config, generated)

**Analog:** self. File is 88 lines; only lines 67 and 76 change. **The file header says it was generated by FlutterFire CLI — do NOT re-run `flutterfire configure` during Phase 8; it would clobber this edit.**

**BEFORE — lines 61-68** (verbatim — `ios` block):
```dart
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAoYwOPlEfHL7ZKiyh8AUJgwln9aJu-f-Y',
    appId: '1:881677813575:ios:822eba72f065e498a8ae62',
    messagingSenderId: '881677813575',
    projectId: 'cryptransfer-96e9f',
    storageBucket: 'cryptransfer-96e9f.firebasestorage.app',
    iosBundleId: 'com.example.cryptransfer',
  );
```

**AFTER — lines 61-68:**
```dart
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAoYwOPlEfHL7ZKiyh8AUJgwln9aJu-f-Y',
    appId: '1:881677813575:ios:822eba72f065e498a8ae62',
    messagingSenderId: '881677813575',
    projectId: 'cryptransfer-96e9f',
    storageBucket: 'cryptransfer-96e9f.firebasestorage.app',
    iosBundleId: 'com.navveennair.cryptransfer',
  );
```

**BEFORE — lines 70-77** (verbatim — `macos` block):
```dart
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAoYwOPlEfHL7ZKiyh8AUJgwln9aJu-f-Y',
    appId: '1:881677813575:ios:822eba72f065e498a8ae62',
    messagingSenderId: '881677813575',
    projectId: 'cryptransfer-96e9f',
    storageBucket: 'cryptransfer-96e9f.firebasestorage.app',
    iosBundleId: 'com.example.cryptransfer',
  );
```

**AFTER — lines 70-77:**
```dart
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAoYwOPlEfHL7ZKiyh8AUJgwln9aJu-f-Y',
    appId: '1:881677813575:ios:822eba72f065e498a8ae62',
    messagingSenderId: '881677813575',
    projectId: 'cryptransfer-96e9f',
    storageBucket: 'cryptransfer-96e9f.firebasestorage.app',
    iosBundleId: 'com.navveennair.cryptransfer',
  );
```

**Untouched anchors** (DO NOT EDIT):
- `web` block (lines 43-51) — no `iosBundleId` field
- `android` block (lines 53-59) — no `iosBundleId` field; `appId` does NOT reference the package name (it's a numeric Firebase app ID)
- `windows` block (lines 79-87) — no `iosBundleId` field

**Header preservation note:** Lines 1-2 contain `// File generated by FlutterFire CLI.` + `// ignore_for_file: type=lint`. Discretion item: planner may add a comment block warning "iosBundleId manually aligned in Phase 8 — do NOT run `flutterfire configure` without re-applying" per RESEARCH.md Open Question #4.

---

### `android/app/google-services.json` (config, build-time)

**Analog:** self. The file is REPLACED WHOLESALE by a Firebase Console download (Wave 0 manual step). Current file is 54 lines and contains a single-app `client[]` array. The post-rename file will contain a two-app `client[]` array.

**BEFORE — current single-app structure** (verbatim from `google-services.json`):
```json
{
  "project_info": {
    "project_number": "881677813575",
    "project_id": "cryptransfer-96e9f",
    "storage_bucket": "cryptransfer-96e9f.firebasestorage.app"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "1:881677813575:android:87c5d27a6a2518eca8ae62",
        "android_client_info": {
          "package_name": "com.example.cryptransfer"
        }
      },
      "oauth_client": [
        {
          "client_id": "881677813575-ecfjblvb7a7q8pnjknn8amob7u8jg5ka.apps.googleusercontent.com",
          "client_type": 1,
          "android_info": {
            "package_name": "com.example.cryptransfer",
            "certificate_hash": "10c2bf7e5d15cb4353d31aad863b3da0943af020"
          }
        },
        ...
      ],
      ...
      "services": {
        "appinvite_service": {
          "other_platform_oauth_client": [
            ...
            {
              "client_id": "881677813575-6s7jceim8carmdn161psc7daabil79li.apps.googleusercontent.com",
              "client_type": 2,
              "ios_info": {
                "bundle_id": "com.example.cryptransfer"
              }
            }
          ]
        }
      }
    }
  ],
  "configuration_version": "1"
}
```

**AFTER — expected post-download two-app structure (schematic — Firebase Console generates the exact bytes):**
```json
{
  "project_info": {
    "project_number": "881677813575",
    "project_id": "cryptransfer-96e9f",
    "storage_bucket": "cryptransfer-96e9f.firebasestorage.app"
  },
  "client": [
    { ...existing entry... "android_client_info": { "package_name": "com.example.cryptransfer" } ... },
    { ...new entry...      "android_client_info": { "package_name": "com.navveennair.cryptransfer" } ... }
  ],
  "configuration_version": "1"
}
```

**Verification commands** (Windows PowerShell, since `jq` may be unavailable):
```powershell
Get-Content android/app/google-services.json | ConvertFrom-Json |
  Select-Object -ExpandProperty client |
  ForEach-Object { $_.client_info.android_client_info.package_name }
# Expected output: TWO lines — "com.example.cryptransfer" AND "com.navveennair.cryptransfer"
```

**Footgun:** Array order is not guaranteed; the Google Services Gradle plugin matches by `package_name` string equality (order-insensitive). The OLD entry's `certificate_hash` (line 21) is preserved; the new entry will lack `certificate_hash` until the Console SHA-1 is registered (deferred — only affects Google Sign-In, not Firestore/Auth basic flows).

---

### `android/app/proguard-rules.pro` (config, build-time) — VERIFY-ONLY

**Analog:** self. **No edit required.** File contains 27 lines of generic keep rules (Flutter, Firebase, Play Services, PointyCastle, Kotlin) — none reference `com.example.*`.

**Verification snippet** (verbatim from `proguard-rules.pro`):
```proguard
# Flutter embedding — must be kept for plugin registration
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
...
# Firebase / Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
...
# PointyCastle / Bouncy Castle (used by pointycastle Dart plugin via JNI on some targets)
-keep class org.bouncycastle.** { *; }
...
# Kotlin stdlib
-keep class kotlin.** { *; }
```

**Required action:** Planner MUST add a verification step that re-reads the file and confirms no `com.example.cryptransfer.*` keep rule has been added since the 2026-05-29 research read. If any such rule exists, RENAME it; otherwise leave file untouched.

---

### `android/app/src/main/AndroidManifest.xml` (config, build-time) — VERIFY-ONLY

**Analog:** self. **No edit required.** Line 40 uses the Gradle `${applicationId}` placeholder, which AGP resolves at manifest-merge time.

**Verification snippet** (verbatim from `AndroidManifest.xml`, lines 37-46):
```xml
        <!-- FileProvider: lets open_file_plus share files from app-private dirs -->
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/provider_paths"/>
        </provider>
```

**Post-rename resolved authority** (computed at build time, not in source):
- `com.navveennair.cryptransfer.fileprovider`

**Required action:** Planner MUST add a verification step that re-reads line 40 to confirm the literal `${applicationId}` placeholder is still in place. If anyone has hardcoded `com.example.cryptransfer.fileprovider`, REPLACE with `${applicationId}.fileprovider`.

---

### Tree deletion: `android/app/src/main/kotlin/com/example/` — DELETE

**No analog.** This is a directory-tree removal, executed AFTER `MainActivity.kt` is moved to its new home (Step 3 of Implementation Order) and AFTER all rename edits are complete.

**Pre-deletion expected state** (RESEARCH.md verified):
```
android/app/src/main/kotlin/com/example/cryptransfer/
├── (MainActivity.kt — already moved out by `git mv`)
└── graphify-out/
    └── cache/
        └── 109e70bf390e73d283b67a98362cef1afb16b6f271be1ddde1b117dbe4e0ea08.json  (stale artifact)
```

**Deletion command:**
```
git rm -rf android/app/src/main/kotlin/com/example/
```

**Post-deletion expected state:**
```
android/app/src/main/kotlin/
└── com/
    └── navveennair/
        └── cryptransfer/
            └── MainActivity.kt
```

**Verification:**
```powershell
Test-Path "android/app/src/main/kotlin/com/example"   # Expected: False
Test-Path "android/app/src/main/kotlin/com/navveennair/cryptransfer/MainActivity.kt"   # Expected: True
```

---

### `test/android/method_channel_naming_test.dart` (test, unit) — OPTIONAL WAVE 0

**Analog:** `test/security/session_wipe_test.dart` (scaffolding pattern only) + `test/security/mem_safety_test.dart` (pure-logic style — no Firestore mock needed).

This test does NOT mock Firebase or exercise channel handlers (which would require `androidTest` instrumented tests, out of scope per RESEARCH.md). It asserts the post-rename string literals match expectations — cheap Dart-side typo insurance.

**Imports + scaffolding pattern** (copy from `test/security/mem_safety_test.dart` lines 1-11):
```dart
import 'package:flutter_test/flutter_test.dart';

// ─── MethodChannel Naming Tests (D-04) ──────────────────────────────────────
//
// Validates the Dart-side MethodChannel string literals match the renamed
// Kotlin constants in MainActivity.kt. These are pure string-literal sanity
// checks — no Flutter widget context or native execution required.

void main() {
  group('METHOD CHANNEL NAMING TESTS', () {
    // ─── TC-CHANNEL-001 ────────────────────────────────────────────────────
    // Decision D-04:
    //   MethodChannel namespaces become package-independent:
    //     com.example.cryptransfer/security → cryptransfer/security
    //     com.example.cryptransfer/file     → cryptransfer/file
    //   Validates Dart consumers carry the expected new string.
    ...
  });
}
```

**Group + `test()` block pattern** (copy from `test/security/session_wipe_test.dart` lines 8-15):
```dart
void main() {
  group('METHOD CHANNEL NAMING TESTS', () {
    setUp(() {
      // No fixture needed — pure string assertions.
    });

    test('TC-CHANNEL-001: security channel string matches expected literal',
      () {
        // ...
      },
    );
  });
}
```

**Assertion style** (copy from `mem_safety_test.dart` lines 30-41 — pure `expect`, no async):
```dart
        expect(
          someValue,
          expectedLiteral,
          reason: 'human-readable why-this-matters explanation',
        );
```

**Planner decision:** RESEARCH.md `Open Questions #1` recommends YES, add this test (cheap insurance, ~20 lines, ~30 min). Planner discretion to skip if D-06 on-device smoke step 5b/5d is deemed sufficient — but document the choice.

**Implementation note:** The test must NOT import the Kotlin side (impossible from Dart). It can either (a) import `security_lifecycle_mixin.dart` + `decrypt_screen.dart` and grep for the expected literal via reflection — fragile, since both fields are `private`/`static const`; OR (b) duplicate the expected string as a top-level constant in the test file and assert intent — clearer but adds a maintenance touch-point. Planner picks the implementation style.

---

## Shared Patterns

### Cross-Language String Pair (Kotlin Constant ↔ Dart MethodChannel)

**Source:** `MainActivity.kt:33-34` (Kotlin) + `security_lifecycle_mixin.dart:24` + `decrypt_screen.dart:52` (Dart)

**Apply to:** Wave 2 of the planner's wave structure — change Kotlin then immediately change BOTH Dart consumers in the same atomic edit batch. Never split across commits.

**Pattern (post-rename — copy verbatim):**

Kotlin side:
```kotlin
private val securityChannel = "cryptransfer/security"
private val fileChannel     = "cryptransfer/file"
```

Dart consumer 1 (`security_lifecycle_mixin.dart`):
```dart
static final _securityChannel =
    const MethodChannel('cryptransfer/security');
```

Dart consumer 2 (`decrypt_screen.dart`):
```dart
static const _fileChannel = MethodChannel('cryptransfer/file');
```

**Why it matters:** `flutter analyze` does NOT cross-check string literals across the Kotlin/Dart boundary. A typo produces a silent `MissingPluginException` at runtime. The `isFlagSecureActive()` safe-fallback at `security_lifecycle_mixin.dart:54-58` masks security-channel typos invisibly; only the task-switcher screenshot test in D-06 step 5b reveals them.

### `${applicationId}` Gradle Placeholder Pattern

**Source:** `AndroidManifest.xml:40`

**Apply to:** Verification step — confirm the placeholder is still in place after the rename. AGP resolves `${applicationId}` to the new value at manifest-merge time during build; no code change needed.

```xml
android:authorities="${applicationId}.fileprovider"
```

### Atomic Multi-File Edit + Single Commit Pattern

**Source:** RESEARCH.md Implementation Order Step 11 (Atomic-commit boundary advice)

**Apply to:** All planning waves — split into atomic editable groups, but bundle into ONE commit at the end of verification. Partial commits leave the tree in an unbuildable state where Kotlin/Dart channel strings disagree → `git bisect` produces broken builds.

**Commit message template** (from RESEARCH.md):
```
chore(android): rename applicationId to com.navveennair.cryptransfer
- Gradle namespace + applicationId
- Kotlin package + physical directory move (MainActivity.kt)
- MethodChannel namespaces decoupled to "cryptransfer/{security,file}"
- firebase_options.dart iosBundleId aligned
- google-services.json regenerated (multi-app)
- Deleted obsolete com/example/ tree + stale graphify-out cache
```

### `flutter clean` Mandatory Reset Pattern

**Source:** RESEARCH.md Implementation Order Step 9 + Footguns #3

**Apply to:** Between Wave 2 (code edits) and Wave 3 (verification). Stale `build/` directory retains old R class with old `BuildConfig.APPLICATION_ID`. Without `flutter clean`, the rebuilt APK may carry stale identifiers.

```
flutter clean
flutter pub get
```

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `android/app/src/main/kotlin/com/navveennair/cryptransfer/MainActivity.kt` (target path) | native bridge | request-response | Target directory does not exist yet — created by `git mv` of the existing file. Pattern IS the moved file. |
| Two-app `google-services.json` post-Console-download | config | build-time | Firebase Console generates the exact bytes; planner cannot pre-write this file. The "pattern" is the manual Wave 0 step (download → replace → verify). |

These are not "missing analogs" in the conventional sense — they are end-states produced by mechanical operations (`git mv`, Console download) rather than by writing new code.

## Metadata

**Analog search scope:**
- `android/app/build.gradle.kts` (full file read)
- `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt` (full file read)
- `lib/core/utils/security_lifecycle_mixin.dart` (full file read)
- `lib/presentation/receiver/decrypt_screen.dart` (lines 1-80 read for channel definition site)
- `lib/firebase_options.dart` (full file read)
- `android/app/google-services.json` (full file read)
- `android/app/proguard-rules.pro` (full file read — verification only)
- `android/app/src/main/AndroidManifest.xml` (full file read — verification only)
- `test/security/session_wipe_test.dart` (first 60 lines — scaffolding template)
- `test/security/mem_safety_test.dart` (first 60 lines — pure-logic style template)
- `test/` directory glob (18 test files listed; no existing test exercises MethodChannel string literals)

**Files scanned:** 10 source files + 18 test file paths enumerated

**Pattern extraction date:** 2026-05-29

**Key invariant carried through to planner:** Every BEFORE/AFTER snippet in this document is verbatim from a live file read on 2026-05-29. The planner can use these snippets as the literal edit payload for `Edit` tool invocations — no paraphrasing was applied.
