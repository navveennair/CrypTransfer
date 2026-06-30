---
phase: 08-applicationid-rename-replace-com-example-cryptransfer-with-p
plan: 01
status: complete
completed_at: 2026-05-29
commit: fc8ec0f
---

# Phase 08 Plan 01 — Summary

## Outcome

**PASS** — applicationId renamed from `com.example.cryptransfer` to `com.navveennair.cryptransfer` across all coupled touchpoints. All D-06 acceptance gates passed.

## D-06 Gate Results

- [x] **D-06.1** `flutter analyze` — No issues found
- [x] **D-06.2** `flutter test` — 107/108 baseline maintained (TC010 pre-existing); TC-WIPE-001..006 all pass
- [x] **D-06.3** `flutter build apk --debug` — APK stamped as `com.navveennair.cryptransfer`
- [x] **D-06.4** APK install on real Android device — `adb install -r` succeeded
- [x] **D-06.5** On-device smoke 5a/5b/5c/5d/5e — all five sub-checks passed

## Files Changed

From `git log -1 --stat fc8ec0f` (atomic commit):

- `android/app/build.gradle.kts` — namespace + applicationId renamed
- `android/app/google-services.json` — regenerated multi-app (both packages registered)
- `android/app/src/main/kotlin/com/example/cryptransfer/MainActivity.kt` → `android/app/src/main/kotlin/com/navveennair/cryptransfer/MainActivity.kt` (git mv rename)
- `lib/core/utils/security_lifecycle_mixin.dart` — MethodChannel string `com.example.cryptransfer/security` → `cryptransfer/security`
- `lib/presentation/receiver/decrypt_screen.dart` — MethodChannel string `com.example.cryptransfer/file` → `cryptransfer/file`
- `lib/firebase_options.dart` — iosBundleId aligned on ios + macos blocks
- `android/app/proguard-rules.pro` — verified unchanged (no package-name keep rules)
- `android/app/src/main/AndroidManifest.xml` — verified unchanged (`${applicationId}.fileprovider` placeholder preserved)
- Deleted: `android/app/src/main/kotlin/com/example/` tree + stale graphify-out cache artifact

## Threat Register Outcomes

| Threat | Disposition |
|--------|-------------|
| T-08-01 (MethodChannel string asymmetry — security) | mitigated — on-device smoke 5b confirmed FLAG_SECURE via task-switcher |
| T-08-02 (build failure — google-services.json mismatch) | mitigated — APK built successfully; Firebase initialized |
| T-08-03 (old com/example/ tree not deleted) | mitigated — tree deleted via git rm -rf |
| T-08-04 (Google Sign-In SHA-1 not registered) | accepted — deferred; email/password auth used for smoke test |
| T-08-05 (kill-switch reactive binding regression) | mitigated — TC-WIPE-001..006 pass; on-device smoke 5c confirmed Firestore cleanup fires |
| T-08-06 (stale BuildConfig.APPLICATION_ID) | mitigated — flutter clean + aapt verification confirmed new package name |
| T-08-07 (flutterfire configure clobber) | accepted — documented; flutterfire configure not run |
| T-08-08 (FileProvider authority hardcoded) | mitigated — Task 2.7 re-verified placeholder; aapt confirmed resolved authority |

## On-Device Smoke Results

- **5a** App launches → login/home screen reached; Firebase.initializeApp did not throw
- **5b** Task-switcher thumbnail blank/blacked-out — FLAG_SECURE working (`cryptransfer/security` channel registered)
- **5c** Receiver mailbox toggle-off → Firestore `users/{uid}.publicKey` deleted within 2-5s — kill-switch reactive binding intact
- **5d** Full send→receive→decrypt→save flow succeeded; decrypted file appeared in /sdcard/Download/ — `cryptransfer/file` channel registered
- **5e** `adb shell pm list packages` returned `package:com.navveennair.cryptransfer`

## Additional Fix (same session)

Role conflict false positive fixed: stale `selectedSenderUid` cleared in sender transaction to prevent role assignment conflict on repeated "Receive File" clicks.

## Open Items for Next Phase

- [ ] SHA-1 registration for release Google Sign-In (deferred per D-04 / A4)
- [ ] Delete old `com.example.cryptransfer` Firebase app entry (deferred per D-05 transition safety net)
- [ ] iOS Firebase setup (deferred — Android-only v1.0)
- [ ] `versionCode`/`versionName` bump (deferred to first Play Store submission)
