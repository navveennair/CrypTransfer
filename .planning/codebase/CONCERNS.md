# Concerns

**Analysis Date:** 2025-04-19

## Technical Debt

### TD-001: ReceiverTransferScreen Missing SessionManager Propagation
- **Severity:** Medium
- **File:** `lib/presentation/receiver/receiver_transfer_screen.dart`
- **Issue:** Navigation to `ReceiverTransferScreen` is automatic but the screen creates its own `TransferRepository` without access to the `SessionManager` from `ReceiverScreen`. If the user backgrounds the app mid-decrypt, `SessionManager.terminated` is set by `ReceiverScreen.didChangeAppLifecycleState`, but `ReceiverTransferScreen` has no lifecycle observer.
- **Fix:** Pass `sessionManager` as a constructor arg or use an `InheritedWidget`/`Provider`.

### TD-002: Firestore Calls Scattered in Presentation Layer
- **Severity:** Medium
- **Files:** Multiple screen files
- **Issue:** Some screens call Firestore directly rather than going through repository layer. This violates the clean architecture boundary.
- **Fix:** Audit screen files for direct `FirebaseFirestore.instance` calls; move to repositories.

### TD-003: Biometric Auth Bypassed
- **Severity:** Low (intentional for thesis testing)
- **File:** `lib/core/utils/biometric_helper.dart`
- **Issue:** Face ID / fingerprint auth is bypassed for thesis demo purposes. Not suitable for production.
- **Fix:** Re-enable before Play Store release.

### TD-004: Incomplete Batch Write Error Handling
- **Severity:** Low
- **File:** `lib/data/repositories/key_repository.dart`, `lib/data/services/encryption_service.dart`
- **Issue:** `WriteBatch.commit()` failures in `selectSenderHandshake()` and `closeReceiverSession()` may leave partial state in Firestore.
- **Fix:** Add retry logic or compensating transactions.

### TD-005: Large Screen Files (God Components)
- **Severity:** Medium
- **Files:**
  - `lib/presentation/receiver/receiver_screen.dart` (~1757 lines)
  - `lib/presentation/sender/sender_screen.dart` (~853 lines)
  - `lib/presentation/session/end_session_screen.dart` (~651 lines)
  - `lib/data/services/encryption_service.dart` (~368 lines)
- **Issue:** Large files are harder to test, review, and modify safely.
- **Fix:** Extract step widgets and helper methods into separate files.

## Security Gaps

### SEC-001: Compute() Isolate Ciphertext Not Zeroed
- **Severity:** Accepted risk (platform limitation)
- **File:** `lib/data/services/encryption_service.dart`
- **Issue:** The encrypted `Uint8List` lives in the compute isolate's heap and is not accessible for `fillRange` zeroing from the main isolate.
- **Status:** Documented in CLAUDE.md Known Open Issues. Inherent Flutter limitation.

### SEC-002: Biometric Gate Disabled
- **Severity:** High (production concern, low for thesis)
- **File:** `lib/core/utils/biometric_helper.dart`
- **Issue:** App can be opened without biometric authentication.
- **Fix:** Re-enable before production.

### SEC-003: No Certificate Pinning
- **Severity:** Low (Firebase SDK handles TLS)
- **Issue:** No custom certificate pinning beyond Firebase's built-in TLS.
- **Status:** Acceptable for Firebase-backed apps; not a gap.

## Performance Bottlenecks

### PERF-001: Plaintext Fully Buffered Before Encryption
- **Severity:** Medium (large files)
- **File:** `lib/presentation/sender/sender_screen.dart`, `lib/data/services/transfer_service.dart`
- **Issue:** Despite 64 KB chunked reads, plaintext is assembled into one `Uint8List` before passing to `compute()`. For very large files (100 MB limit), this creates a large heap allocation.
- **Fix:** Streaming encryption (out of scope for thesis; accepted).

### PERF-002: Notification Sorting Client-Side
- **Severity:** Low
- **File:** `lib/presentation/home/notifications_screen.dart`
- **Issue:** Notifications sorted in-memory after Firestore fetch, not via Firestore `orderBy`.
- **Fix:** Add `orderBy('createdAt', descending: true)` to Firestore query.

### PERF-003: Transfer Progress Screen Re-Subscription Risk
- **Severity:** Low
- **File:** `lib/presentation/sender/transfer_progress_screen.dart`
- **Issue:** Firestore listener set up on build — if widget rebuilds, a second subscription may form.
- **Fix:** Initialize stream in `initState()` as stable field.

## Fragile Areas

### FRAG-001: `applicationId` Uses Placeholder
- **Severity:** High (Play Store)
- **File:** `android/app/build.gradle.kts`
- **Issue:** `applicationId` is still `com.example.cryptransfer`. Must be changed before publishing.
- **Fix:** Update to final app ID before Play Store release.

### FRAG-002: `key.properties` Missing = Debug Signing Fallback
- **Severity:** Low (by design)
- **File:** `android/app/build.gradle.kts`
- **Issue:** If `android/key.properties` is absent, release builds silently fall back to debug signing.
- **Fix:** Documented in CLAUDE.md; new machine setup instructions present.

### FRAG-003: `firebase_options.dart` Contains Platform API Keys
- **Severity:** Low (expected for Firebase Flutter apps)
- **File:** `lib/firebase_options.dart`
- **Issue:** Google API keys embedded in source. Firebase security rules + App Check mitigate risk.
- **Status:** Standard Flutter/Firebase pattern; acceptable.

### FRAG-004: Thesis-Specific Figure Numbering in Docs
- **Severity:** Low
- **Issue:** Thesis document figure numbering needs fixing before submission.
- **Fix:** Manual update to thesis document.

## Dependencies at Risk

| Package | Risk | Notes |
|---------|------|-------|
| `pointycastle` | Medium | Unmaintained in some versions; PointyCastle is the only Dart-native RSA/AES lib. |
| `flutter_secure_storage` | Low | Platform-dependent; Android Keystore backed. |
| `fake_cloud_firestore` | Low (test-only) | Must track Firebase SDK version parity. |

## Known Gaps from CLAUDE.md

- `ReceiverTransferScreen` does not propagate `SessionManager` (documented, not fixed)
- `compute()` isolate ciphertext not zeroed (accepted platform limitation)
- Biometric auth disabled (intentional, pre-viva)
- Chapter 3 + 5 thesis updates pending
- Fix figure numbering in thesis
- Update `applicationId` before Play Store release

---

*Concerns analysis: 2025-04-19*
