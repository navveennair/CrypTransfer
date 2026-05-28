# Phase 8: applicationId Rename - Context

**Gathered:** 2026-05-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the placeholder `com.example.cryptransfer` Android package with a production package across every coupled touchpoint, so the app can be published to Google Play without regression.

**In scope:**
- `android/app/build.gradle.kts` — `namespace` (line 22) and `applicationId` (line 43)
- Kotlin package declaration and physical directory path for `MainActivity.kt`
- MethodChannel namespaces referenced from Kotlin (`MainActivity.kt`) AND Dart (`security_lifecycle_mixin.dart`, `decrypt_screen.dart`)
- `android/app/google-services.json` — regenerated from Firebase Console
- `lib/firebase_options.dart` — `iosBundleId` on `ios` and `macos` entries
- `android/app/proguard-rules.pro` — confirmed currently has NO `com.example.*` rules (verified during discussion); no edit required, but planner must re-check
- Deletion of the old `android/app/src/main/kotlin/com/example/` directory tree (including stale `graphify-out/cache/` artifact inside)

**Must remain regression-free:** `flutter analyze` clean, full test suite passes, FLAG_SECURE pre-flight functional, kill-switch reactive binding (`SessionManager.stateStream → EncryptionService.bindSession`) intact, all MethodChannel calls succeed.

**Out of scope:** Any iOS-specific build/signing work, any Firestore data migration, any UI changes, any new features.

</domain>

<decisions>
## Implementation Decisions

### New Package Name
- **D-01:** `applicationId` = `com.navveennair.cryptransfer` (personal reverse-domain; replaces `com.example.cryptransfer` which is reserved by Google and blocks Play Store)
- **D-02:** Gradle `namespace` (line 22 of `android/app/build.gradle.kts`) also = `com.navveennair.cryptransfer` — both keys match. Kotlin package declaration and physical directory path (`android/app/src/main/kotlin/com/navveennair/cryptransfer/MainActivity.kt`) follow.
- **D-03:** `lib/firebase_options.dart` — `iosBundleId` on the `ios` and `macos` `FirebaseOptions` entries (lines 67, 76) also = `com.navveennair.cryptransfer`. Cosmetic-only on Android-only v1.0; keeps the codebase aligned so a future iOS phase does not trip on stale identifiers.

### MethodChannel Naming
- **D-04:** MethodChannel namespaces become **package-independent**:
  - `com.example.cryptransfer/security` → `cryptransfer/security`
  - `com.example.cryptransfer/file` → `cryptransfer/file`
  - Decouples the cross-language bridge from the `applicationId`. Resolves the watch-list item in `.planning/codebase/CONCERNS.md` §5 ("applicationId, Kotlin package, MethodChannel namespace, and google-services.json all encode the same string — changing one without the others silently breaks the bridge"). Future renames will no longer ripple into Dart files.
  - Touches three files this one time: `android/app/src/main/kotlin/com/navveennair/cryptransfer/MainActivity.kt` (constants `securityChannel`, `fileChannel`, and the KDoc block at lines 20-25), `lib/core/utils/security_lifecycle_mixin.dart` (line 24), `lib/presentation/receiver/decrypt_screen.dart` (line 52).

### Firebase / google-services.json
- **D-05:** Add `com.navveennair.cryptransfer` as a **second** Android app inside the existing Firebase project `cryptransfer-96e9f` (do NOT create a new project). Keep the existing `com.example.cryptransfer` Android app entry registered during transition as a safety net. Regenerate `google-services.json` from the Firebase Console — the regenerated file will contain both Android app entries. Existing users, audit logs, handshakes, friendships, and Firestore rules are preserved.

### Verification Plan
- **D-06:** Phase-level acceptance bar:
  1. `flutter analyze` exits 0 with no issues
  2. Full test suite passes (currently 107/108 per STATE.md — must remain at that bar)
  3. `flutter build apk --debug` succeeds
  4. APK installs on a real Android device
  5. On-device smoke test confirms: app launches; FLAG_SECURE blocks screenshot attempt in task switcher; kill-switch fires (toggle receiver mailbox off, observe Firestore `users/{uid}` cleanup, observe sender stream revert)
- **D-07:** Old Kotlin directory tree `android/app/src/main/kotlin/com/example/` is **deleted** in this phase (including the stale `graphify-out/cache/` artifact at `android/app/src/main/kotlin/com/example/cryptransfer/graphify-out/`). After deletion the only Kotlin source tree is `android/app/src/main/kotlin/com/navveennair/cryptransfer/`.

### Claude's Discretion
- Order of operations across the multi-system rename (Firebase Console action vs. local code edits vs. Gradle changes). Recommended sequence: Firebase Console first (so `google-services.json` is available locally before any code edits) → namespace+applicationId in `build.gradle.kts` → physical directory move + Kotlin package declaration → MethodChannel constants in `MainActivity.kt` → Dart MethodChannel string updates → `firebase_options.dart` iosBundleId → delete old `com/example/` tree → run verification.
- Wave/plan partitioning (single plan with sequenced tasks vs. split across waves).
- Exact atomic commit grouping (one commit per concern vs. one bundled commit).
- Whether to capture `flutter clean` between gradle config changes (likely yes).
- Whether to bump `versionCode` / `versionName` in this phase (likely no — rename is pre-release and `versionCode` is read from `flutter.versionCode`).
- Handling of `AndroidManifest.xml` FileProvider authority: line 40 uses `android:authorities="${applicationId}.fileprovider"` — the `${applicationId}` Gradle placeholder resolves at build time, so no manual edit is required. Planner must verify this is still true after the rename.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase blocker source-of-truth
- `.planning/codebase/CONCERNS.md` §3 — defines the rename as a Play Store blocker and lists the four coupling fixes (Kotlin package, MethodChannel, google-services.json, proguard-rules)
- `.planning/codebase/CONCERNS.md` §5 — flags the cross-language coupling watch-list item that D-04 (stable MethodChannel name) resolves

### Files to modify
- `android/app/build.gradle.kts` (lines 22, 43) — `namespace` + `applicationId`
- `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt` (line 1: package declaration; lines 20, 25: KDoc; lines 33-34: `securityChannel`, `fileChannel` constants) — file moves to `android/app/src/main/kotlin/com/navveennair/cryptransfer/MainActivity.kt`
- `lib/core/utils/security_lifecycle_mixin.dart` (line 24) — MethodChannel consumer of `/security`
- `lib/presentation/receiver/decrypt_screen.dart` (line 52) — MethodChannel consumer of `/file`
- `lib/firebase_options.dart` (lines 67, 76) — `iosBundleId` on `ios` and `macos` entries
- `android/app/google-services.json` (lines 12, 20, 45) — regenerated from Firebase Console; will contain BOTH `com.example.cryptransfer` and `com.navveennair.cryptransfer` Android app entries

### Files to verify untouched but adjacent
- `android/app/proguard-rules.pro` — verified during discussion to currently contain NO `com.example.cryptransfer.*` keep rules (only Flutter/Firebase/PointyCastle/Kotlin generic rules). Planner must re-confirm before closing the phase.
- `android/app/src/main/AndroidManifest.xml` (line 40) — uses `${applicationId}.fileprovider` Gradle placeholder; auto-updates via build; no manual edit required.

### Tree to delete
- `android/app/src/main/kotlin/com/example/` — entire directory tree after the Kotlin source physically moves to `com/navveennair/cryptransfer/`. Includes stale `graphify-out/cache/` artifact.

### Project context
- `.planning/PROJECT.md` — milestone v1.0 is Android-only; iOS scope deferred (informs why iosBundleId update in D-03 is cosmetic)
- `CLAUDE.md` → Pre-Release section — already lists this rename as pending
- `.planning/STATE.md` — Phase 8 description and "Depends on: Phase 7"

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `android/app/build.gradle.kts` already wires up release signing via git-ignored `android/key.properties` with a debug-signing fallback. Rename does not affect signing.
- `AndroidManifest.xml` uses `${applicationId}` placeholder for FileProvider authorities — Gradle handles the substitution at build time; no code change needed there.
- `flutter.compileSdkVersion`, `flutter.minSdkVersion`, `flutter.targetSdkVersion`, `flutter.versionCode`, `flutter.versionName` all read from Flutter's defaults — none reference the package name.

### Established Patterns
- MethodChannel naming today follows the package-prefix convention (`{applicationId}/{channel}`). D-04 intentionally breaks this pattern in favor of a stable channel name to permanently decouple Kotlin↔Dart from `applicationId`.
- All crypto runs in Dart `compute()` isolates; no native key material lives in Kotlin. The MethodChannel `/security` handler `clearSession` only calls `System.gc()` as a hint. This means renaming the channel is purely a string-rename operation with no behavioral risk beyond mis-typing.
- `flutter analyze` clean is the standing bar (achieved through Phase 07.1 layer decoupling refactor).

### Integration Points
- Kotlin → Dart: `MainActivity.kt` registers two `setMethodCallHandler`s — both must use the new namespace strings.
- Dart → Kotlin: `security_lifecycle_mixin.dart` (line 24) calls `MethodChannel('com.example.cryptransfer/security').invokeMethod('isFlagSecureActive')` from inside `SenderScreen._encryptFile()` and other crypto pre-flights. `decrypt_screen.dart` (line 52) calls `MethodChannel('com.example.cryptransfer/file').invokeMethod('saveToDownloads')` from inside `_saveAndWipe()`.
- Firebase: `google-services.json` is read by the `com.google.gms.google-services` Gradle plugin (declared at line 15 of `build.gradle.kts`) at build time. The file must contain an entry whose `package_name` matches `applicationId`, or the build fails with `Manifest merger failed`.
- FileProvider: `AndroidManifest.xml` authority `${applicationId}.fileprovider` flows through to `open_file_plus` (consumer of FileProvider). Authority string changes implicitly when `applicationId` changes — no Dart-side change required.

</code_context>

<specifics>
## Specific Ideas

- The rename must NOT touch any Firestore document, collection name, or security rule. Existing data is preserved by keeping the same Firebase project (`cryptransfer-96e9f`) per D-05.
- The Firebase Console step is a manual, interactive action (the user — Navveen — has to log in to Firebase Console, navigate to project settings, add the new Android app, download the new `google-services.json`). Planner should flag the corresponding task as `autonomous: false` and make it a hard prerequisite for the local-code waves.
- After rename, the existing `com.example.cryptransfer` Firebase Android app entry stays registered. The Console step does NOT delete it. This is deliberate per D-05 (safety net during transition).

</specifics>

<deferred>
## Deferred Ideas

- **Cross-language coupling guard scanner** — `.planning/codebase/CONCERNS.md` §5 suggests a `silent_guardian.ps1` rule (or `flutter analyze`-level check) that compares `applicationId`, Kotlin package, MethodChannel namespaces, and `google-services.json` `package_name` fields and fails if they diverge. D-04 (stable MethodChannel name) removes one of the three sources of divergence in Phase 8, but the guard itself is out of scope and lands in a future phase.
- **Delete the `com.example.cryptransfer` Firebase Android app registration** — left in place during transition per D-05. A later cleanup phase can remove it from the Firebase Console once we are confident no stale builds remain in circulation.
- **iOS / macOS Firebase setup** — D-03 updates the `iosBundleId` string only. Actually wiring iOS to a Firebase iOS app (regenerating `GoogleService-Info.plist`, configuring Xcode) is deferred to whenever an iOS phase eventually runs.
- **`versionCode` / `versionName` bump** — Phase 8 is pre-release; no version bump in this phase. First Play Store submission will set those values.

</deferred>

---

*Phase: 08-applicationid-rename-replace-com-example-cryptransfer-with-p*
*Context gathered: 2026-05-29*
