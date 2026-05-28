---
phase: 8
slug: applicationid-rename-replace-com-example-cryptransfer-with-p
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-29
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Synthesized from `08-RESEARCH.md` → `## Validation Architecture` section.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `flutter_test` (Flutter SDK built-in) |
| **Config file** | none — default project layout (`test/` directory) |
| **Quick run command** | `flutter analyze` |
| **Full suite command** | `flutter test` |
| **Estimated runtime** | analyze ~5s · test ~30-60s · debug APK build ~60-120s · on-device smoke ~3-5 min |

---

## Sampling Rate

- **After every task commit:** Run `flutter analyze` (catches Dart syntax + import drift; ~5s)
- **After every plan wave:** Run `flutter test` (full suite; must hold 107/108 baseline)
- **Before `/gsd-verify-work`:** All five D-06 acceptance gates must pass:
  1. `flutter analyze` → 0 issues
  2. `flutter test` → 107/108 baseline maintained
  3. `flutter build apk --debug` → succeeds
  4. `adb install -r app-debug.apk` → installs on real device
  5. On-device smoke (5a launch / 5b FLAG_SECURE / 5c kill-switch / 5d save-to-Downloads / 5e APK identity)
- **Max feedback latency:** ~5s for analyze · ~60s for full suite · on-device steps are manual

---

## Per-Task Verification Map

Phase 8 has no formal REQ-IDs — mapping derived from D-01..D-07 in CONTEXT.md.

| Decision | Plan | Wave | Behavior to Verify | Test Type | Automated Command | File Exists | Status |
|----------|------|------|--------------------|-----------|-------------------|-------------|--------|
| D-01 / D-02 | 01 | 3 | APK install ID = `com.navveennair.cryptransfer` | smoke (build) | `flutter build apk --debug && aapt dump badging build/app/outputs/flutter-apk/app-debug.apk \| Select-String "package: name"` | ✅ Flutter SDK | ⬜ pending |
| D-02 | 01 | 3 | Kotlin compiles + R class generated under new namespace | smoke (build) | `flutter build apk --debug` (failure mode: R class import error) | ✅ Flutter SDK | ⬜ pending |
| D-03 | 01 | 2 | `firebase_options.dart` iosBundleId == `com.navveennair.cryptransfer` | unit (grep) | `Select-String "com.navveennair.cryptransfer" lib/firebase_options.dart` returns 2 matches | ✅ shell | ⬜ pending |
| D-04 (security channel string parity) | 01 | 2 | Kotlin `securityChannel` == Dart `MethodChannel('cryptransfer/security')` | unit (NEW) | `flutter test test/android/method_channel_naming_test.dart` | ❌ Wave 0 (optional) | ⬜ pending |
| D-04 (file channel string parity) | 01 | 2 | Kotlin `fileChannel` == Dart `MethodChannel('cryptransfer/file')` | unit (NEW) | `flutter test test/android/method_channel_naming_test.dart` | ❌ Wave 0 (optional) | ⬜ pending |
| D-04 (security runtime) | 01 | 3 | FLAG_SECURE pre-flight returns true on protected window | manual smoke | task-switcher screenshot test on real device (D-06 step 5b) | manual | ⬜ pending |
| D-04 (file runtime) | 01 | 3 | `saveToDownloads` succeeds; file visible in `/sdcard/Download/` | manual smoke | full receive flow on real device (D-06 step 5d) | manual | ⬜ pending |
| D-05 (multi-app) | 01 | 1 | google-services.json contains both `package_name` entries | unit (file) | PowerShell `Get-Content android/app/google-services.json \| ConvertFrom-Json \| Select-Object -ExpandProperty client \| ForEach-Object { $_.client_info.android_client_info.package_name }` returns both strings | ✅ shell | ⬜ pending |
| D-05 (Firebase init) | 01 | 3 | `Firebase.initializeApp()` in main() does not throw | smoke (runtime) | App launch test (D-06 step 5a) | manual | ⬜ pending |
| D-06 (test bar) | 01 | 3 | Existing test suite stays at 107/108 baseline | regression | `flutter test` | ✅ Flutter SDK | ⬜ pending |
| D-06 (analyze bar) | 01 | 3 | `flutter analyze` returns 0 issues | regression | `flutter analyze` | ✅ Flutter SDK | ⬜ pending |
| D-07 (delete tree) | 01 | 2 | `com/example/` directory does not exist | unit (file system) | PowerShell `Test-Path "android/app/src/main/kotlin/com/example"` returns False | ✅ shell | ⬜ pending |
| Kill-switch regression | 01 | 3 | `SessionManager.stateStream → EncryptionService.bindSession` chain unaffected | regression | `flutter test test/security/session_wipe_test.dart` (TC-WIPE-001..006) | ✅ existing | ⬜ pending |
| proguard re-confirmation | 01 | 2 | `proguard-rules.pro` has NO `com.example.cryptransfer.*` rules | unit (grep) | `Select-String "com.example.cryptransfer" android/app/proguard-rules.pro` returns 0 matches | ✅ shell | ⬜ pending |
| AndroidManifest auto-resolution | 01 | 3 | FileProvider authority resolves to `com.navveennair.cryptransfer.fileprovider` | smoke (build) | `aapt dump xmltree build/app/outputs/flutter-apk/app-debug.apk AndroidManifest.xml \| Select-String "fileprovider"` | ✅ Flutter SDK | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

The existing test suite does NOT exercise the renamed code paths. Per RESEARCH.md → Wave 0 Gaps:

- [ ] `test/android/method_channel_naming_test.dart` — covers D-04 (string parity Kotlin↔Dart for both channels)
  - Asserts: `SecurityLifecycleMixin` channel string == `'cryptransfer/security'`
  - Asserts: `DecryptScreen` channel string == `'cryptransfer/file'`
  - **OPTIONAL** — planner discretion. Skip is acceptable IF the on-device smoke (D-06 step 5b + 5d) is performed and recorded.
- No framework install required (`flutter_test` is part of Flutter SDK; already in pubspec).

---

## Manual-Only Verifications

| Behavior | Decision | Why Manual | Test Instructions |
|----------|----------|------------|-------------------|
| FLAG_SECURE blocks task-switcher screenshot | D-04 (security) / D-06 step 5b | Cannot be exercised in `flutter_test` (requires real window) or emulator (emulator screenshot APIs bypass FLAG_SECURE) | On real device: app to background → open task switcher → attempt screenshot → confirm blank thumbnail or "screenshot blocked" toast |
| Kill-switch fires Firestore cleanup | D-04 / D-06 step 5c | Requires live Firestore connection + real OS lifecycle events | Login → Receiver screen → toggle mailbox ON → toggle OFF → verify in Firebase Console that `users/{uid}` doc has `publicKey` and `selectedSenderUid` deleted |
| Save-to-Downloads works end-to-end | D-04 (file) / D-06 step 5d | Requires native MediaStore.Downloads write + real file system | Sender → upload file → Receiver → accept → decrypt → save → verify file appears in `/sdcard/Download/` via file manager |
| APK identity stamps correctly | D-01 / D-06 step 5e | Requires built APK artifact | `aapt dump badging build/app/outputs/flutter-apk/app-debug.apk \| Select-String "package: name"` returns `com.navveennair.cryptransfer` |
| Firebase project still serves data | D-05 / D-06 step 5a | Requires live Firebase Auth + Firestore | App launches → email/password login succeeds → Active Connections list populates → confirms `Firebase.initializeApp` matched new package to existing project |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify OR documented manual smoke step in D-06
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (analyze runs after every task)
- [ ] Wave 0 covers MethodChannel string parity (optional new test, or accepted as on-device-smoke-only)
- [ ] No watch-mode flags
- [ ] Feedback latency: analyze ~5s · test ~60s · build ~120s · smoke manual
- [ ] `nyquist_compliant: true` set in frontmatter (flip after Wave 0 decision is recorded)

**Approval:** pending
