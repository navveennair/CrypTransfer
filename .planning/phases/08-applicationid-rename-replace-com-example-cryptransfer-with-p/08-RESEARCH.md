# Phase 8: applicationId Rename — Research

**Researched:** 2026-05-29
**Domain:** Android build identity (applicationId / namespace / Kotlin package), Flutter MethodChannel string coupling, Firebase multi-app `google-services.json`, FileProvider authority resolution
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** `applicationId` = `com.navveennair.cryptransfer` (personal reverse-domain; replaces `com.example.cryptransfer` which is reserved by Google and blocks Play Store).
- **D-02:** Gradle `namespace` (line 22 of `android/app/build.gradle.kts`) also = `com.navveennair.cryptransfer` — both keys match. Kotlin package declaration and physical directory path (`android/app/src/main/kotlin/com/navveennair/cryptransfer/MainActivity.kt`) follow.
- **D-03:** `lib/firebase_options.dart` — `iosBundleId` on the `ios` and `macos` `FirebaseOptions` entries (lines 67, 76) also = `com.navveennair.cryptransfer`. Cosmetic-only on Android-only v1.0; keeps the codebase aligned so a future iOS phase does not trip on stale identifiers.
- **D-04:** MethodChannel namespaces become package-independent: `com.example.cryptransfer/security` → `cryptransfer/security`; `com.example.cryptransfer/file` → `cryptransfer/file`. Touches three files this one time: `android/app/src/main/kotlin/com/navveennair/cryptransfer/MainActivity.kt` (constants `securityChannel`, `fileChannel`, and the KDoc block at lines 20-25), `lib/core/utils/security_lifecycle_mixin.dart` (line 24), `lib/presentation/receiver/decrypt_screen.dart` (line 52).
- **D-05:** Add `com.navveennair.cryptransfer` as a **second** Android app inside the existing Firebase project `cryptransfer-96e9f` (do NOT create a new project). Keep the existing `com.example.cryptransfer` Android app entry registered during transition as a safety net. Regenerate `google-services.json` from the Firebase Console — the regenerated file will contain both Android app entries. Existing users, audit logs, handshakes, friendships, and Firestore rules are preserved.
- **D-06:** Phase-level acceptance bar:
  1. `flutter analyze` exits 0 with no issues
  2. Full test suite passes (currently 107/108 per STATE.md — must remain at that bar)
  3. `flutter build apk --debug` succeeds
  4. APK installs on a real Android device
  5. On-device smoke test confirms: app launches; FLAG_SECURE blocks screenshot attempt in task switcher; kill-switch fires (toggle receiver mailbox off, observe Firestore `users/{uid}` cleanup, observe sender stream revert)
- **D-07:** Old Kotlin directory tree `android/app/src/main/kotlin/com/example/` is **deleted** in this phase (including the stale `graphify-out/cache/` artifact at `android/app/src/main/kotlin/com/example/cryptransfer/graphify-out/`). After deletion the only Kotlin source tree is `android/app/src/main/kotlin/com/navveennair/cryptransfer/`.

### Claude's Discretion

- Order of operations across the multi-system rename (Firebase Console action vs. local code edits vs. Gradle changes). Recommended sequence: Firebase Console first → `build.gradle.kts` → Kotlin physical move + package declaration → MethodChannel constants in `MainActivity.kt` → Dart MethodChannel strings → `firebase_options.dart` iosBundleId → delete old `com/example/` tree → run verification.
- Wave/plan partitioning (single plan with sequenced tasks vs. split across waves).
- Exact atomic commit grouping (one commit per concern vs. one bundled commit).
- Whether to capture `flutter clean` between gradle config changes (likely yes).
- Whether to bump `versionCode` / `versionName` in this phase (likely no — `versionCode` is read from `flutter.versionCode`).
- Handling of `AndroidManifest.xml` FileProvider authority (line 40 already uses `${applicationId}.fileprovider` placeholder — Gradle resolves at build time; verify only).

### Deferred Ideas (OUT OF SCOPE)

- Cross-language coupling guard scanner (`.planning/codebase/CONCERNS.md` §5 suggested rule comparing applicationId / Kotlin package / google-services.json package_name).
- Delete the `com.example.cryptransfer` Firebase Android app registration (left in place during transition per D-05; cleanup phase later).
- iOS / macOS Firebase setup — D-03 updates the iosBundleId string only. Actually wiring iOS to a Firebase iOS app is deferred.
- `versionCode` / `versionName` bump.

</user_constraints>

## Summary

- The phase is **purely a coordinated string-rename** across 7 file edits, 1 physical directory move, 1 directory deletion, and 1 manual Firebase Console action. No application logic, no Firestore schema, no security rules change.
- **All locked decisions (D-01 through D-07) are technically sound.** AGP 8.11.1 + KGP 2.2.20 fully support the `namespace` DSL (`[VERIFIED: AGP 7.3+ release notes — namespace DSL stable since AGP 7.3, 2022]`). The `com.google.gms.google-services` plugin 4.3.15 correctly picks the `package_name` entry matching `applicationId` when a `google-services.json` contains multiple registered apps `[VERIFIED: Google Services Plugin docs]`. The `${applicationId}.fileprovider` placeholder in `AndroidManifest.xml` auto-resolves at build time `[VERIFIED: Android docs + manifest read]`.
- **Critical sequencing requirement:** Firebase Console step MUST happen before local code edits (per D-05). The Gradle build will fail with `Manifest merger failed — Manifest property holder` or `No matching client found for package name 'com.navveennair.cryptransfer'` if `applicationId` is changed before the new file is on disk. The Console step is `autonomous: false` — Navveen must perform it manually.
- **One footgun specific to this codebase:** MethodChannel namespaces are referenced by **string literal** on both sides (Kotlin constant + Dart `const MethodChannel(...)`), so a typo or asymmetric rename will produce a silent `MissingPluginException` only on the screen that uses the broken channel — `flutter analyze` will not catch it. Validation requires either a real-device smoke test (already in D-06) or a `flutter test` that constructs both channels and asserts string equality.

**Primary recommendation:** Single plan, 3 waves: (W1) Firebase Console + google-services.json download (manual, autonomous: false, blocks downstream); (W2) all 6 code/config edits in parallel-safe order culminating in `flutter clean`; (W3) verification (analyze + tests + debug APK build + on-device smoke). Bundle into one atomic commit only after all D-06 acceptance gates pass — partial commits will leave the tree in an unbuildable state.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Android app identity (Play Store ID) | Android Build (Gradle) | — | `applicationId` is a Gradle property that controls install ID and Play Console upload identity |
| Kotlin source organisation | Android Source Tree | — | Package declaration must match physical directory per Kotlin compiler rules |
| R class / BuildConfig generation | Android Build (Gradle) | — | `namespace` controls the package of generated code; independent of `applicationId` semantically but conventionally matched |
| Cross-language method invocation | Flutter Engine | Android + Dart strings | MethodChannel routing uses string equality between Kotlin handler registration and Dart MethodChannel constructor |
| Firebase project association | Firebase Gradle Plugin | `google-services.json` | Plugin matches `applicationId` against `package_name` entries at build time |
| FileProvider URI authority | Android Manifest (build-time substitution) | — | `${applicationId}.fileprovider` placeholder is resolved by AGP during manifest merge |

## Decision Audit

Each locked decision verified against platform requirements and best practice:

| Decision | Technically Sound? | Notes |
|----------|-------------------|-------|
| **D-01** `com.navveennair.cryptransfer` | ✅ YES | Valid Java/Kotlin package syntax (3 segments, lowercase, no reserved words). Not in `com.example.*` reserved space. No Play Store namespace conflict expected. |
| **D-02** namespace = applicationId | ✅ YES — **strongly recommended** | Android docs: *"It is recommended that you keep the application ID the same as the namespace"* `[CITED: developer.android.com/build/configure-app-module]`. Avoids R class confusion. |
| **D-03** iosBundleId update | ✅ YES (cosmetic) | No Android impact. iOS Xcode project (`ios/Runner.xcodeproj/project.pbxproj`) ALSO contains 6 occurrences of `com.example.cryptransfer` — but **D-03 does not require these to change** (out of scope per CONTEXT.md). |
| **D-04** Stable MethodChannel names | ✅ YES | Decouples Kotlin↔Dart bridge from applicationId. Resolves the §5 watch-list item in CONCERNS.md. One-time rename cost; permanent benefit. |
| **D-05** Multi-app Firebase + Console first | ✅ YES | The `com.google.gms.google-services` plugin selects the `package_name` matching `applicationId` `[VERIFIED: Google Services Plugin docs]`. Both old + new entries coexisting is the standard "flavor / migration" pattern. |
| **D-06** Acceptance bar | ✅ YES | Five-gate bar covers all regression surfaces. On-device smoke is the only path that catches MethodChannel string mismatches (unit tests cannot — see Validation Architecture). |
| **D-07** Delete `com/example/` tree | ✅ YES | Includes stale `graphify-out/cache/109e70bf390e73d283b67a98362cef1afb16b6f271be1ddde1b117dbe4e0ea08.json` artifact (verified present). After deletion the only Kotlin source tree is `com/navveennair/cryptransfer/`. |

**No conflicts surfaced. All seven decisions are platform-compliant and may proceed as-locked.**

**Adjacent observation (informational, not a re-decision):** iOS Xcode `PRODUCT_BUNDLE_IDENTIFIER = com.example.cryptransfer` appears at 6 lines in `ios/Runner.xcodeproj/project.pbxproj` (lines 375, 391, 408, 423, 554, 576). This is OUT OF SCOPE for Phase 8 (deferred per CONTEXT.md "iOS / macOS Firebase setup"), but the planner should note: if the future iOS phase is ever run, it will need to update both the Xcode project AND the Firebase Console (add an iOS app). D-03's update to `iosBundleId` in `firebase_options.dart` is consistent with that future state.

## Implementation Order

The user decisions explicitly endorse this sequence. Recommended decomposition into atomic, individually-revertible steps:

```
STEP 0 — PRECONDITION (NOT a code task)
  └── User commits any uncommitted work (UI-FIX-SUMMARY.md, .planning/STATE.md
      modifications) OR explicitly accepts they will be carried through this
      phase. Phase 8 should start on a clean working tree.

STEP 1 — FIREBASE CONSOLE  (manual; autonomous: false)
  ├── Navigate to: console.firebase.google.com → cryptransfer-96e9f
  ├── Settings → Project settings → "Your apps"
  ├── Click "Add app" → Android
  ├── Package name: com.navveennair.cryptransfer
  ├── App nickname: optional ("CrypTransfer (production)")
  ├── Debug signing certificate SHA-1: optional for debug builds
  │     (must be added later for release Google Sign-In; not required now)
  ├── Register app → Download google-services.json
  ├── Replace android/app/google-services.json with downloaded file
  └── Verify: file contains TWO "client" array entries, one with
      "package_name": "com.example.cryptransfer", one with
      "package_name": "com.navveennair.cryptransfer".

  GATE: Stop here if Console step fails. All downstream work assumes the new
  google-services.json is on disk.

STEP 2 — GRADLE CONFIG  (single edit)
  └── android/app/build.gradle.kts
      ├── line 22: namespace = "com.navveennair.cryptransfer"
      └── line 43: applicationId = "com.navveennair.cryptransfer"

STEP 3 — KOTLIN PHYSICAL MOVE  (file system operation)
  ├── Create directory: android/app/src/main/kotlin/com/navveennair/cryptransfer/
  ├── git mv android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt
  │           android/app/src/main/kotlin/com/navveennair/cryptransfer/MainActivity.kt
  └── Verify: only MainActivity.kt was moved (the stale graphify-out/
              artifact stays in the doomed com/example/ tree to be deleted in
              Step 8).

STEP 4 — KOTLIN PACKAGE DECLARATION + KDOC + MethodChannel CONSTANTS
  └── android/app/src/main/kotlin/com/navveennair/cryptransfer/MainActivity.kt
      ├── line 1:  package com.navveennair.cryptransfer
      ├── line 20: KDoc — "com.example.cryptransfer/security" → "cryptransfer/security"
      ├── line 25: KDoc — "com.example.cryptransfer/file"     → "cryptransfer/file"
      ├── line 33: private val securityChannel = "cryptransfer/security"
      └── line 34: private val fileChannel     = "cryptransfer/file"

STEP 5 — DART MethodChannel CONSUMER (1) — security_lifecycle_mixin.dart
  └── lib/core/utils/security_lifecycle_mixin.dart
      └── line 24: const MethodChannel('cryptransfer/security')

STEP 6 — DART MethodChannel CONSUMER (2) — decrypt_screen.dart
  └── lib/presentation/receiver/decrypt_screen.dart
      └── line 52: const MethodChannel('cryptransfer/file')

STEP 7 — firebase_options.dart iosBundleId
  └── lib/firebase_options.dart
      ├── line 67: iosBundleId: 'com.navveennair.cryptransfer',
      └── line 76: iosBundleId: 'com.navveennair.cryptransfer',

STEP 8 — DELETE OLD KOTLIN TREE
  └── git rm -rf android/app/src/main/kotlin/com/example/
      (includes the stale com/example/cryptransfer/graphify-out/cache/ artifact)

STEP 9 — flutter clean  (mandatory)
  ├── flutter clean
  └── This forces:
      - regeneration of build/  (where applicationId is stamped)
      - rebuild of .dart_tool/
      - Gradle re-evaluation of namespace + applicationId
      - manifest merger with new ${applicationId}.fileprovider authority

STEP 10 — VERIFICATION (D-06 acceptance bar)
  ├── flutter analyze         → expect "No issues found"
  ├── flutter test            → expect 107/108 (Phase 07 baseline)
  ├── flutter build apk --debug
  │     → expect:  app-debug.apk built; APK install ID stamps as
  │                 com.navveennair.cryptransfer
  ├── adb install -r build/app/outputs/flutter-apk/app-debug.apk
  └── On-device smoke (3 sub-checks):
      a) App launches to home screen
      b) Attempt screenshot in task switcher → blocked (FLAG_SECURE)
         (validates security MethodChannel still wired)
      c) Open Receiver → toggle mailbox on → toggle off
         → confirm Firestore users/{uid} has publicKey deleted
         (validates kill-switch reactive binding still intact)

STEP 11 — ATOMIC COMMIT (after all gates green)
  └── Single commit for the rename, e.g.:
        chore(android): rename applicationId to com.navveennair.cryptransfer
        - Gradle namespace + applicationId
        - Kotlin package + physical directory move (MainActivity.kt)
        - MethodChannel namespaces decoupled to "cryptransfer/{security,file}"
        - firebase_options.dart iosBundleId aligned
        - google-services.json regenerated (multi-app)
        - Deleted obsolete com/example/ tree + stale graphify-out cache
```

**Atomic-commit boundary advice:** A single commit is correct. Splitting (e.g., one commit per file) would leave intermediate revisions where Dart-Kotlin MethodChannel strings disagree → broken builds in `git bisect` history. The git working tree is allowed to be in an unbuildable state for 30-60 minutes during the rename — but no commit should land in that state.

## Per-Touchpoint Notes

### `android/app/build.gradle.kts`

**Two lines to change** — both must change in the same edit (Gradle will not fail if only one changes, but the build artifact and the R class will then be misaligned).

```kotlin
// line 22 — BEFORE
namespace = "com.example.cryptransfer"
// line 22 — AFTER
namespace = "com.navveennair.cryptransfer"

// line 43 — BEFORE
applicationId = "com.example.cryptransfer"
// line 43 — AFTER
applicationId = "com.navveennair.cryptransfer"
```

**Gotcha:** The `signingConfigs` block above (lines 31-40) reads from `android/key.properties` which is git-ignored. That file does NOT reference the package name — nothing to change there. Release signing keeps working unchanged `[VERIFIED: build.gradle.kts read]`.

**Gotcha:** `flutter.compileSdkVersion`, `flutter.minSdkVersion`, etc. are Flutter Gradle Plugin properties — none reference the package name. Untouched `[VERIFIED: build.gradle.kts read]`.

### `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt` → `.../com/navveennair/cryptransfer/MainActivity.kt`

**Physical move + 5 edits inside the moved file:**

```kotlin
// line 1 — BEFORE
package com.example.cryptransfer
// line 1 — AFTER
package com.navveennair.cryptransfer

// line 20 — KDoc — BEFORE
 * Channel 1 — "com.example.cryptransfer/security"
// line 20 — KDoc — AFTER
 * Channel 1 — "cryptransfer/security"

// line 25 — KDoc — BEFORE
 * Channel 2 — "com.example.cryptransfer/file"
// line 25 — KDoc — AFTER
 * Channel 2 — "cryptransfer/file"

// line 33 — BEFORE
private val securityChannel = "com.example.cryptransfer/security"
// line 33 — AFTER
private val securityChannel = "cryptransfer/security"

// line 34 — BEFORE
private val fileChannel     = "com.example.cryptransfer/file"
// line 34 — AFTER
private val fileChannel     = "cryptransfer/file"
```

**Gotcha:** Use `git mv` (not plain `mv`) so git history follows the file. With plain `mv`, git records "delete + add" and blame is lost.

**Gotcha:** Kotlin compiler enforces that the package declaration matches the physical directory **for IDE navigation only** — `kotlinc` will accept a mismatch and compile. So the Gradle build will succeed even if the package declaration is mis-typed; symptom only appears in IDE warnings. The on-device smoke (D-06) catches the runtime crash that would result.

### `lib/core/utils/security_lifecycle_mixin.dart`

**One line:**

```dart
// line 24 — BEFORE
static final _securityChannel =
    const MethodChannel('com.example.cryptransfer/security');
// line 24 — AFTER
static final _securityChannel =
    const MethodChannel('cryptransfer/security');
```

**Gotcha:** The string must match EXACTLY the Kotlin constant in `MainActivity.kt:33`. No leading slash, no trailing slash, lowercase only. If `flutter analyze` is clean but FLAG_SECURE pre-flight returns `true` on emulator despite the bug — that's because the mixin's `isFlagSecureActive()` catches `MissingPluginException` and returns `true` as a safe fallback (line 54-58 of the file). This means a typo here is INVISIBLE to unit tests AND to on-device smoke unless you actually verify FLAG_SECURE via the task switcher screenshot test in D-06.

### `lib/presentation/receiver/decrypt_screen.dart`

**One line:**

```dart
// line 52 — BEFORE
static const _fileChannel = MethodChannel('com.example.cryptransfer/file');
// line 52 — AFTER
static const _fileChannel = MethodChannel('cryptransfer/file');
```

**Gotcha:** Unlike the security channel, the file channel has NO silent fallback. If this string is mis-typed, the receiver's "Save & Continue" button (line 604 of decrypt_screen.dart) will throw `MissingPluginException` when invoking `saveToDownloads`. The exception lands in the `catch (e)` block at line 332 and surfaces as a SnackBar — so the user sees "Save failed: MissingPluginException(...)". On-device smoke test in D-06 must include a full receive-and-save flow OR add a unit test that constructs both MethodChannels and asserts string equality (see Validation Architecture).

### `lib/firebase_options.dart`

**Two lines** (lines 67 and 76 — both `ios` and `macos` entries):

```dart
// line 67 — BEFORE
iosBundleId: 'com.example.cryptransfer',
// line 67 — AFTER
iosBundleId: 'com.navveennair.cryptransfer',

// line 76 — BEFORE
iosBundleId: 'com.example.cryptransfer',
// line 76 — AFTER
iosBundleId: 'com.navveennair.cryptransfer',
```

**Gotcha:** The file header says `// File generated by FlutterFire CLI`. If anyone runs `flutterfire configure` in the future, it will OVERWRITE this file based on the Firebase Console state. Since we are not adding an iOS Firebase app in Phase 8 (deferred per CONTEXT.md), running `flutterfire configure` is OUT OF SCOPE and would clobber our manual edit. The planner should explicitly flag: **do NOT run `flutterfire configure` in Phase 8** — the edit is intentional and isolated.

### `android/app/google-services.json`

**Replaced wholesale** by download from Firebase Console (Step 1). Expected post-condition: the file contains a `"client"` array with **two** entries:

```json
{
  "client": [
    { ...existing... "android_client_info": { "package_name": "com.example.cryptransfer" } ... },
    { ...new...      "android_client_info": { "package_name": "com.navveennair.cryptransfer" } ... }
  ]
}
```

**Gotcha:** The order of the two entries in the `client[]` array is not guaranteed by Firebase Console (sometimes new last, sometimes new first). The `com.google.gms.google-services` plugin matches by `package_name` string equality — order is irrelevant `[VERIFIED: Google Services Plugin docs]`.

**Gotcha:** The `oauth_client[].android_info.certificate_hash` in the current file (line 21) is tied to the existing `com.example.cryptransfer` debug keystore. The new app entry will NOT have a certificate_hash until you add the debug SHA-1 in the Console (only needed for Google Sign-In — not Firestore/Auth basic flows). For Phase 8 the new entry can ship without it; Google Sign-In may fail until the cert is registered, but Phase 02.1's Google Sign-In is only one auth path of two (email/password still works).

**Gotcha:** The file is normally CHECKED INTO git in this codebase (it's not in `.gitignore`). Replacing it produces a normal `git diff` — review the diff to confirm the OLD entry is preserved and a NEW entry is added.

### `android/app/proguard-rules.pro`

**RE-VERIFIED during this research:** No `com.example.cryptransfer.*` keep rules present. The file contains only Flutter (`io.flutter.*`), Firebase (`com.google.firebase.*`), Google Play Services (`com.google.android.gms.*`), PointyCastle (`org.bouncycastle.*`), and Kotlin stdlib (`kotlin.*`) keep rules `[VERIFIED: file read at line 1-27]`. **NO EDIT REQUIRED.**

The planner MUST include a verification step (re-read the file before closing the phase) per CONTEXT.md `canonical_refs → Files to verify untouched but adjacent`.

### `android/app/src/main/AndroidManifest.xml`

**RE-VERIFIED:** Line 40 reads `android:authorities="${applicationId}.fileprovider"` — the `${applicationId}` is a Gradle manifest placeholder. AGP substitutes it during the `processDebugMainManifest` / `processReleaseMainManifest` task at build time. After Phase 8, the resolved authority becomes `com.navveennair.cryptransfer.fileprovider` automatically `[VERIFIED: AndroidManifest.xml read + Android docs]`. **NO EDIT REQUIRED.**

**Gotcha:** Any Dart-side hardcoded reference to the FileProvider authority string would break. `decrypt_screen.dart` uses `open_file` (pubspec confirms `open_file: ^3.3.2`) which uses its own internal FileProvider that resolves via the manifest at runtime — no Dart string to fix `[VERIFIED: pubspec.lock + open_file package docs]`.

### Tree to delete — `android/app/src/main/kotlin/com/example/`

**Pre-rename state (verified):**
```
android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt
android/app/src/main/kotlin/com/example/cryptransfer/graphify-out/cache/109e70bf390e73d283b67a98362cef1afb16b6f271be1ddde1b117dbe4e0ea08.json
```

**Post-rename target state:**
```
android/app/src/main/kotlin/com/navveennair/cryptransfer/MainActivity.kt
```

**Gotcha:** The stale `graphify-out/cache/` artifact (109e70bf...json) is buried inside the OLD Kotlin package directory. It was created by `/graphify` running with `cwd` set to the Kotlin source root at some point. Confirm it has no references in `graphify-out/` proper (the toplevel one). If it is the only remaining reference under `com/example/`, then `rm -rf android/app/src/main/kotlin/com/example/` removes both MainActivity.kt (already moved) and the stale cache in one operation.

**Gotcha:** On Windows, `git rm -rf` works but the underlying file may be retained in the OS file system cache. After deletion, run `git status` to confirm no stragglers, and `ls android/app/src/main/kotlin/` to verify only `com/navveennair/` remains.

## Footguns / Landmines

| # | Footgun | Impact | Mitigation |
|---|---------|--------|------------|
| 1 | Skip Firebase Console step, change `applicationId` first | Build fails: `No matching client found for package name 'com.navveennair.cryptransfer'` from google-services plugin | Hard-prerequisite ordering: Console step is Wave 0, blocks all subsequent waves |
| 2 | MethodChannel string typo (Kotlin/Dart asymmetry) | Silent runtime `MissingPluginException`. Security channel: invisible (mixin swallows). File channel: surfaces as SnackBar at save time. `flutter analyze` does NOT catch this. | Treat both pairs as **string-literal pairs**: change Kotlin then immediately change Dart in same wave. Add post-rename unit test (see Validation). On-device smoke MUST include FLAG_SECURE task-switcher check AND full save-to-Downloads receive flow. |
| 3 | Skip `flutter clean` between rename and rebuild | Stale R class in `build/` retains old package; `BuildConfig.APPLICATION_ID` resolves to `com.example.cryptransfer` at runtime | `flutter clean` is a mandatory step between rename and verification. Also wipes `.dart_tool/` to force MethodChannel string re-resolution at compile time. |
| 4 | Hot reload after MethodChannel string change | Hot reload does NOT propagate native channel handler re-registration. Old channel still bound; new Dart code sends to dead channel | Always full restart (stop app, `flutter run` again) after MethodChannel changes `[VERIFIED: Flutter docs on MethodChannel + hot reload limitations]` |
| 5 | google-services.json replaced but `applicationId` not yet updated | Build succeeds (old entry still matches) but new APK still ships as `com.example.cryptransfer` | The verification step MUST inspect actual APK install ID: `aapt dump badging build/app/outputs/flutter-apk/app-debug.apk | grep package` |
| 6 | `flutterfire configure` accidentally run during Phase 8 | Overwrites `lib/firebase_options.dart` based on current Firebase Console state — would CLOBBER the manual iosBundleId edit | Planner explicitly excludes this command. Phase 8 modifies `firebase_options.dart` by hand. |
| 7 | Delete `com/example/` BEFORE moving `MainActivity.kt` | Lost source file. Recovery via `git restore` or `git checkout HEAD --`. | Step ordering: physical move FIRST (Step 3), package declaration update (Step 4), DELETE LAST (Step 8). |
| 8 | Old debug-cache APK retained on test device | `adb install -r` overlays but does not always clean state. Sometimes confuses "is this the new APK?" check | `adb uninstall com.example.cryptransfer` BEFORE installing new APK. New `applicationId` means the OS sees them as different apps anyway — old install stays on device until manually uninstalled. |
| 9 | Kotlin package declaration not matching physical directory | Compiles (kotlinc tolerates) but IDE navigation breaks; warnings hidden | Step 4 (package declaration) directly follows Step 3 (physical move) — same wave, same review. |
| 10 | Firestore Security Rules tied to UID identity NOT package name | None — Firestore rules use `request.auth.uid`, not `applicationId`. Existing users + data preserved unchanged. | Already validated by D-05 (same Firebase project). No action. |
| 11 | Google Sign-In SHA-1 not registered for new app entry | Google Sign-In fails on new APK (`12500` or `10` error code) | Out of scope for Phase 8 verification; verification uses email/password auth path. Cert registration becomes part of a future Play Store submission phase. |
| 12 | iOS Xcode project still references `com.example.cryptransfer` | Builds succeed; iOS-side will produce inconsistent identifier when iOS phase eventually runs | OUT OF SCOPE per CONTEXT.md `<deferred>`. Planner does not touch `ios/Runner.xcodeproj/project.pbxproj`. |

## Validation Architecture

> Per Nyquist Dimension 8 (`workflow.nyquist_validation: true` in `.planning/config.json`).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `flutter_test` (Flutter SDK built-in) |
| Config file | none — uses default project layout (`test/` directory) |
| Quick run command | `flutter test test/security/mem_safety_test.dart -r expanded` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

Phase 8 has no formal REQ-IDs. Mapping derived from D-01..D-07:

| Decision | Behavior to verify | Test Type | Automated Command | File Exists? |
|----------|-------------------|-----------|-------------------|-------------|
| D-01 / D-02 | APK install ID = `com.navveennair.cryptransfer` | smoke (build) | `flutter build apk --debug && aapt dump badging build/app/outputs/flutter-apk/app-debug.apk \| Select-String "package: name"` | ✅ Flutter SDK |
| D-02 | Kotlin compiles + R class generated under new namespace | smoke (build) | `flutter build apk --debug` (failure mode: R class import error in MainActivity.kt) | ✅ Flutter SDK |
| D-03 | `firebase_options.dart` iosBundleId == `com.navveennair.cryptransfer` | unit (string literal) | `flutter analyze` (catches malformed Dart only — no behavior to test on Android-only build) + grep verification | ✅ Flutter SDK |
| D-04 (security) | FLAG_SECURE pre-flight returns `true` on protected window | manual smoke | task-switcher screenshot test on real device (D-06 step 5b) | manual |
| D-04 (security) | MethodChannel string equality Kotlin↔Dart | unit | NEW — see Wave 0 Gaps below | ❌ Wave 0 |
| D-04 (file) | `saveToDownloads` succeeds and file appears in `/sdcard/Download/` | manual smoke | full receive flow on real device (D-06 step 5) | manual |
| D-05 | google-services.json contains both `package_name` entries | unit (file content) | `jq '.client[].android_client_info.package_name' android/app/google-services.json` returns both strings | shell command |
| D-05 | FirebaseApp initializes successfully with new applicationId | smoke (runtime) | App launch test (D-06 step 5a) — `Firebase.initializeApp()` in main() must not throw | manual |
| D-06 | Existing test suite stays at 107/108 baseline | regression | `flutter test` | ✅ Flutter SDK |
| D-06 | `flutter analyze` returns 0 issues | regression | `flutter analyze` | ✅ Flutter SDK |
| D-07 | `com/example/` directory does not exist | unit (file system) | PowerShell `Test-Path "android/app/src/main/kotlin/com/example"` returns False | shell command |
| Kill-switch reactive binding | `SessionManager.stateStream` → `EncryptionService.bindSession` chain unaffected | regression | `flutter test test/security/session_wipe_test.dart` (TC-WIPE-001..006) | ✅ existing |

### Sampling Rate

- **Per task commit:** `flutter analyze` — fast (~5s), catches dart syntax errors and import drift
- **Per wave merge:** `flutter test` — full suite (~30-60s), catches regression in 107/108 baseline
- **Phase gate (D-06):** all five acceptance bar items must pass before `/gsd-verify-work` is invoked. On-device smoke test is non-automatable but is the ONLY test that catches MethodChannel string typos.

### Wave 0 Gaps

The existing test suite does NOT exercise the renamed code paths:
- No test constructs a `MethodChannel('cryptransfer/security')` or `MethodChannel('cryptransfer/file')` (search verified: `grep MethodChannel test/` returns no matches).
- No test verifies the string equality between Kotlin constants in `MainActivity.kt` and Dart constants in `security_lifecycle_mixin.dart` / `decrypt_screen.dart`.
- No test asserts file-system layout (i.e., that `com/example/` is gone post-rename).

**Recommendation: ADD ONE OPTIONAL UNIT TEST.** A pure-Dart string-literal sanity check that imports the two consumers and asserts the channel name. This catches the most common footgun (Dart-side typo) without requiring native execution. The Kotlin-side typo is not catchable in `flutter test`; it requires either an `androidTest` instrumented test (large addition) OR the on-device smoke step in D-06 (already mandatory). Recommendation is that the unit test is the cheap insurance and the on-device smoke is the canonical proof.

**Suggested Wave 0 deliverable (planner discretion):**

```
- [ ] test/android/method_channel_naming_test.dart  — covers D-04
       Asserts:
         - SecurityLifecycleMixin imports compile (channel string present)
         - DecryptScreen imports compile (channel string present)
         - String pattern matches expected new names
```

If the planner judges the on-device smoke (D-06 step 5b/5c) sufficient and decides not to add this test, that is acceptable — the cost-benefit is marginal because the smoke step IS mandatory and IS the canonical proof. Document the choice either way.

**No framework install needed** (`flutter_test` is part of the Flutter SDK already in pubspec).

### On-Device Smoke Test (mandatory — D-06 step 5)

| # | Action | Expected | Validates |
|---|--------|----------|-----------|
| 5a | Launch APK on real Android device | App opens to home screen (login or main) | applicationId / Firebase init / Manifest valid |
| 5b | Send app to background; from task switcher, attempt screenshot | Screenshot blocked or shows blank thumbnail | `MainActivity.onCreate` FLAG_SECURE intact; `cryptransfer/security` channel handler registered |
| 5c | Login → Receiver → toggle mailbox ON → toggle mailbox OFF | Firestore `users/{uid}` has `publicKey` deleted; `selectedSenderUid` deleted | Kill-switch reactive binding (`SessionManager.stateStream` → `EncryptionService.bindSession` → `closeReceiverSession`) intact |
| 5d | Full sender→receiver transfer flow with file save (recommended add) | `saveToDownloads` succeeds; file visible in `/sdcard/Download/` | `cryptransfer/file` channel handler registered + native `MediaStore.Downloads` write works |
| 5e | Inspect APK package identity | `aapt dump badging app-debug.apk` shows `package: name='com.navveennair.cryptransfer'` | applicationId rename actually stamped |

**Recommendation:** Make 5d explicit — it is the ONLY check that catches a `cryptransfer/file` channel typo. The current D-06 step 5 lists three sub-checks; the planner should expand to four (add 5d) and treat the inspection of APK identity (5e) as part of the build step (`aapt` invocation right after `flutter build apk --debug`).

## Rollback Procedure

**Risk assessment:** This phase is medium-risk. The rename is mechanical and reversible, but failure modes can hide until APK runtime.

**Forward path** is committed atomically (single commit at Step 11 of Implementation Order). This makes rollback a single `git revert HEAD` operation **plus** one manual Firebase Console action.

**Rollback steps if APK is broken post-merge:**

```
STEP 1 — REVERT CODE
  └── git revert HEAD --no-edit
      Reverts: build.gradle.kts, MainActivity.kt (back to com/example/),
               security_lifecycle_mixin.dart, decrypt_screen.dart,
               firebase_options.dart, google-services.json,
               restores com/example/ tree.

STEP 2 — CLEAN BUILD
  ├── flutter clean
  └── flutter pub get

STEP 3 — REBUILD
  └── flutter build apk --debug
      └── Should produce com.example.cryptransfer APK as before

STEP 4 — FIREBASE CONSOLE  (manual — leave new entry registered)
  └── The new com.navveennair.cryptransfer Firebase Android app entry
      stays registered in Console. This is harmless. Do NOT delete it —
      it will be reused when Phase 8 is retried.

STEP 5 — VERIFY ROLLBACK
  ├── adb uninstall com.navveennair.cryptransfer  (remove broken install)
  ├── adb install -r build/app/outputs/flutter-apk/app-debug.apk
  └── Verify on-device: app launches; FLAG_SECURE works; kill-switch works
```

**One-way doors flagged:**

- **Play Store package name lock:** Once an APK is uploaded to Play Console with `applicationId = X`, the same Play Console listing can NEVER accept an upload with `applicationId ≠ X`. **For Phase 8 this is NOT a one-way door** — no Play Console listing has been created yet (per ROADMAP "Pre-Release"). The rename happens before first upload. **Implication:** Phase 8 must complete and stabilize BEFORE any Play Console upload occurs. After the first Play Store upload, the chosen `applicationId` is permanent for that listing.
- **Firebase Console — adding an app:** Reversible. Apps can be deleted from a Firebase project. Per D-05, however, we deliberately leave both apps registered during transition — no removal needed in the success path or the rollback path.
- **`git mv` of MainActivity.kt:** Reversible via `git revert` or `git checkout HEAD~1 -- <path>`. Git history is preserved (`git log --follow MainActivity.kt` works across the rename).

**No catastrophic / unrecoverable operations exist in Phase 8.** All edits are reversible; Firebase project data is preserved (per D-05); Firestore schema unchanged.

## Open Questions

1. **Should Wave 0 add a Dart unit test for MethodChannel string parity?**
   - What we know: existing tests do not cover this; the failure mode is real (silent MissingPluginException on security channel; SnackBar error on file channel); on-device smoke catches it.
   - What's unclear: whether the marginal cost (~30 min to write a 20-line test) is worth the marginal benefit (catches the typo in CI before APK is built).
   - Recommendation: **YES, add it.** Cheap insurance; documents intent.

2. **Does the planner want to incorporate Steps 5d and 5e into D-06 explicitly?**
   - What we know: D-06 step 5 currently lists three sub-checks (launch, FLAG_SECURE, kill-switch). Adding "5d: full save-to-Downloads flow" closes the `cryptransfer/file` channel verification gap. Adding "5e: `aapt dump badging` APK identity check" closes the "did the rename actually stamp" gap.
   - What's unclear: whether expanding the on-device smoke from 3 → 5 sub-checks crosses a Discretion-vs-Decision line.
   - Recommendation: **Treat as Claude's Discretion** — the planner can expand the smoke test without re-litigating D-06.

3. **Is the planner authorized to require `adb uninstall com.example.cryptransfer` before installing the new APK?**
   - What we know: After rename, the new APK has a different `applicationId` — the OS treats it as a different app. The old install remains on the device unless manually uninstalled. This is not a blocker for verification (the new APK installs fine), but it can confuse on-device testing if the user has two CrypTransfer icons in the launcher.
   - Recommendation: **Include `adb uninstall com.example.cryptransfer` as a non-fatal step** in the verification script. If the device does not have the old app, the command fails harmlessly with `DELETE_FAILED_INTERNAL_ERROR` or `Failure [DELETE_FAILED_DEVICE_POLICY_MANAGER]` — the planner should `|| true` it.

4. **Should the planner take any preventive action against `flutterfire configure` being run later?**
   - What we know: The `firebase_options.dart` header explicitly says "File generated by FlutterFire CLI". Anyone re-running `flutterfire configure` will overwrite the iosBundleId D-03 sets.
   - Recommendation: **Add a comment block at the top of `firebase_options.dart` after the rename** noting "iosBundleId values manually aligned for future iOS phase — DO NOT run `flutterfire configure` without re-applying D-03 from Phase 8". Treats as Claude's Discretion. The planner can choose whether to add this annotation.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | All build steps | (assumed yes — project has been actively built) | (`flutter --version` to check) | — |
| `flutter analyze` | D-06 step 1 | ✓ (built-in) | bundled with Flutter | — |
| `flutter test` | D-06 step 2 | ✓ (built-in) | bundled with Flutter | — |
| `flutter build apk --debug` | D-06 step 3 | ✓ (built-in) | bundled with Flutter | — |
| `adb` (Android SDK platform-tools) | D-06 step 4 install + uninstall | (likely yes — Flutter setup includes it) | — | manual file install via device |
| `aapt` (Android SDK build-tools) | Verification step 5e (recommended) | (likely yes — Flutter setup includes it) | — | `unzip -p app-debug.apk AndroidManifest.xml` + manual inspection (worse) |
| Real Android device or emulator | D-06 step 4-5 | (assumed yes — Navveen does on-device UAT regularly) | Android 10+ recommended for MediaStore | emulator (Android 10+) works but can't test screenshot blocking realistically |
| Firebase Console access | D-05 / Step 1 | (assumed yes — Navveen owns `cryptransfer-96e9f`) | n/a (web UI) | none — manual step is mandatory |
| `jq` (optional) | google-services.json sanity check | (uncertain on Windows) | — | PowerShell `Get-Content google-services.json \| ConvertFrom-Json \| Select-Object -Expand client` |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** Only `jq` (Windows) — readily replaced with PowerShell JSON commands.

## Sources

### Primary (HIGH confidence)

- `android/app/build.gradle.kts` — verified namespace + applicationId both at `com.example.cryptransfer` (lines 22, 43)
- `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt` — verified package declaration, KDoc, channel constants
- `android/settings.gradle.kts` — verified AGP 8.11.1 + KGP 2.2.20 (both >> 7.3 minimum for namespace DSL)
- `android/app/google-services.json` — verified single `package_name: "com.example.cryptransfer"` entry pre-rename
- `android/app/proguard-rules.pro` — RE-VERIFIED no `com.example.cryptransfer.*` keep rules (only generic Flutter/Firebase/PointyCastle/Kotlin)
- `android/app/src/main/AndroidManifest.xml` — verified `${applicationId}.fileprovider` placeholder at line 40
- `lib/firebase_options.dart` — verified iosBundleId on lines 67 + 76
- `lib/core/utils/security_lifecycle_mixin.dart` — verified MethodChannel string at line 24
- `lib/presentation/receiver/decrypt_screen.dart` — verified MethodChannel string at line 52
- `ios/Runner.xcodeproj/project.pbxproj` — verified 6 occurrences of `com.example.cryptransfer` (DEFERRED — out of scope)
- `.planning/codebase/CONCERNS.md` §3 and §5 — phase blocker source-of-truth
- [Android Developers — Configure the app module (namespace vs applicationId)](https://developer.android.com/build/configure-app-module)
- [Google Services Gradle Plugin docs](https://developers.google.com/android/guides/google-services-plugin)

### Secondary (MEDIUM confidence — WebSearch + cross-verified)

- [Understanding namespace and applicationId in Android Gradle (Medium)](https://medium.com/@MahabubKarim/understanding-namespace-and-applicationid-in-android-gradle-718c685db3d2) — corroborates that namespace ≥ AGP 7.3 and namespace ≈ applicationId is the recommendation
- [open_file pub.dev package](https://pub.dev/packages/open_file) — confirms `${applicationId}.fileProvider` pattern; verifies no Dart-side hardcoded authority
- [MissingPluginException causes — Omi AI](https://www.omi.me/blogs/flutter-errors/missingpluginexceptionno-implementation-found-for-method-in-flutter-causes-and-how-to-fix) — confirms hot-reload does not propagate MethodChannel changes; full restart required
- [Multiple bundle_id in google-services.json — Flutter issue #40536](https://github.com/flutter/flutter/issues/40536) — confirms multi-app pattern works; plugin selects by `applicationId`

### Tertiary (LOW confidence — single source / not officially verified)

- None used in this research. All claims are backed by code reads OR documented sources.

## Project Constraints (from CLAUDE.md)

- **Static analysis bar:** `flutter analyze` MUST exit 0 with "No issues found" after every change. Validated 2026-05-26 baseline.
- **Test bar:** Full suite passing per CLAUDE.md → Completed Features section. Phase 8 must not regress 107/108 baseline (STATE.md).
- **Security guardrails:** Per CLAUDE.md scanner rules — `MainActivity.kt`-resident MethodChannel handlers and the Kotlin-Dart bridge are flagged as VERIFIED only by the presence of `MethodChannel` registration. The rename preserves these patterns intact; no scanner rules need updating.
- **graphify sync:** CLAUDE.md → graphify section instructs rebuilding the knowledge graph after code changes (`/graphify . --update`). The planner should include this as a non-blocking post-phase step (Discretion).
- **Git commit conventions:** CLAUDE.md does not enforce a strict commit format, but `.planning/config.json` has `commit_docs: true` — research and plan documents are committed alongside code changes.
- **Theme system / design tokens:** No UI changes in Phase 8. Theme files untouched.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The user (Navveen) has Firebase Console owner access to `cryptransfer-96e9f` | Implementation Order Step 1 | Phase blocked at Wave 0 until access is regained (Console manual step) |
| A2 | The user has an Android device or running emulator for D-06 step 4-5 smoke test | Validation Architecture | Phase cannot reach the D-06 acceptance bar without on-device verification — would have to fall back to emulator (acceptable but cannot test physical screenshot blocking realistically) |
| A3 | The 107/108 baseline test pass-rate from STATE.md remains green when re-run | Validation Architecture | If a regression has snuck in since 2026-05-26, Phase 8 verification will surface it — the planner should treat any new failure as Phase 8's responsibility and triage before merging |
| A4 | The `com.example.cryptransfer` Firebase Android app entry's `oauth_client[].android_info.certificate_hash` is tied to the dev debug keystore — Google Sign-In may break on new APK until SHA-1 is registered for the new app entry | Per-Touchpoint Notes → google-services.json | Google Sign-In is one of two auth paths (email/password works regardless). If verification uses Google Sign-In, may fail — switch to email/password path for D-06 step 5a. Cert registration deferred. |
| A5 | The stale `graphify-out/cache/*.json` artifact inside `com/example/cryptransfer/graphify-out/` has no live references — deleting it is safe | Per-Touchpoint Notes → Tree to delete | If something somehow references this artifact by path, the rebuild of the graph (`/graphify . --update`) will re-generate it elsewhere. Low risk. |

**All other claims in this document are VERIFIED (file reads, code inspection) or CITED (linked sources in Sources section).**

## Metadata

**Confidence breakdown:**
- Standard stack / Decision audit: **HIGH** — direct file reads + official docs corroboration
- Implementation order: **HIGH** — derived from explicit CONTEXT.md sequencing + locked decisions
- Footguns: **HIGH** — drawn from documented Flutter/Android behavior + code-specific knowledge (e.g., `isFlagSecureActive()` swallows `MissingPluginException`)
- Validation architecture: **HIGH** for what exists; **MEDIUM** for the recommended new unit test (advisory, not load-bearing)
- Rollback: **HIGH** — atomic-commit-revert pattern is standard; one-way doors enumerated and confirmed absent

**Research date:** 2026-05-29
**Valid until:** 2026-06-30 (stable platform domain; AGP / Firebase plugin / FlutterFire versions move slowly)

## RESEARCH COMPLETE
