---
phase: quick-260526
plan: sxe
type: execute
wave: 1
depends_on: []
files_modified:
  - test/security/session_wipe_test.dart
  - lib/data/repositories/key_repository.dart
  - lib/data/repositories/handshake_repository.dart
  - scripts/security_audit_report.dart
autonomous: true
requirements: []
user_setup: []

must_haves:
  truths:
    - "No references to rsa_key_transfers collection exist in production code"
    - "fromUserId/toUserId fields replaced with senderId/receiverId where applicable"
    - "Deterministic ID comments in neutral_handshakes preserved (intentional design)"
    - "All tests pass after cleanup"
  artifacts:
    - path: "lib/data/repositories/key_repository.dart"
      provides: "Auto-ID handshake methods only, no rsa_key_transfers references"
    - path: "lib/data/repositories/handshake_repository.dart"
      provides: "Neutral handshakes with deterministic IDs (kept intentional)"
    - path: "test/security/session_wipe_test.dart"
      provides: "Updated test references from rsa_key_transfers to handshakes"
  key_links:
    - from: "KeyRepository"
      to: "handshakes (auto-ID)"
      via: "selectSenderHandshake(), sendPublicKey()"
      pattern: "collection(FirebaseConstants.handshakes).where"
    - from: "HandshakeRepository"
      to: "neutral_handshakes (deterministic)"
      via: "sendProposal(), acceptProposal()"
      pattern: "doc('${_uid}_$partnerUid')"
---

<objective>
Remove unused deterministic ID implementation logics that were part of the old `rsa_key_transfers` model. The system is now unified on auto-ID for handshakes (`handshakes` collection) and deterministic IDs for connection proposals (`neutral_handshakes` collection). Clean up legacy references while preserving intentional deterministic patterns.

Purpose: Eliminate dead code paths and test references to the deprecated `rsa_key_transfers` collection and related `fromUserId`/`toUserId` field patterns.
Output: Cleaned codebase with no references to abandoned patterns; auto-ID and neutral handshake logic remains intact.
</objective>

<execution_context>
@C:\Users\navve\projects\cryptransfer\.claude\get-shit-done\workflows\execute-plan.md
@C:\Users\navve\projects\cryptransfer\.claude\get-shit-done\templates\summary.md
</execution_context>

<context>
@C:\Users\navve\projects\cryptransfer\.planning\STATE.md
@C:\Users\navve\projects\cryptransfer\CLAUDE.md

## Context: Old vs. New Architecture

**Old Model (DEPRECATED):**
- Collection: `rsa_key_transfers` (auto-ID docs)
- Fields: `fromUserId`, `toUserId`, `publicKey`
- Pattern: Receiver publishes key to multiple senders; senders query and listen

**New Model (CURRENT):**
- Collection: `handshakes` (auto-ID docs)
- Fields: `senderId`, `receiverId`, `publicKey`
- Pattern: Receiver selects sender; atomic WriteBatch via `selectSenderHandshake()`; sender streams authorized docs

**Intentional Pattern (KEPT):**
- Collection: `neutral_handshakes` (deterministic IDs)
- Doc ID: `${proposerId}_${partnerId}`
- Fields: `proposerId`, `partnerId`, `status`
- Pattern: Connection proposals before role assignment; deterministic ID ensures idempotent re-sends

## Key Finding

The term "deterministic ID" in handshake_repository.dart comments refers to the connection-layer proposals, which use `${uid}_${partner}` as doc IDs. This is **intentional and correct** for the neutral handshakes model and should NOT be removed.

The cleanup is scoped to:
1. Test references to old `rsa_key_transfers` collection
2. Stale comments mentioning the old model in key_repository.dart
3. Audit report references to removed test cases
</context>

<tasks>

<task type="auto">
  <name>Task 1: Audit and document all deprecated references</name>
  <files>none (read-only grep)</files>
  <action>
Grep the codebase for:
- `rsa_key_transfers` (old collection name)
- `fromUserId` in Firestore operations (old field name, not param names)
- `toUserId` in Firestore operations (old field name, not param names)

Exclude:
- Parameter names like `fromUserId` in method signatures (e.g., `Future<void> saveReceivedKey(String fromUserId, ...)` — this is a method param, not a Firestore field)
- `neutral_handshakes` deterministic ID patterns (intentional)
- `senderId`/`receiverId` patterns (correct new model)
- Comments that are informational

Document findings in a grep output summary to guide cleanup tasks.
  </action>
  <verify>
grep "rsa_key_transfers" lib/ test/ scripts/ 2>/dev/null | wc -l
grep "collection.*rsa_key_transfers" lib/ test/ scripts/ 2>/dev/null
  </verify>
  <done>Grep audit complete; identified all rsa_key_transfers references and fromUserId/toUserId field operations in Firestore queries</done>
</task>

<task type="auto">
  <name>Task 2: Remove rsa_key_transfers references from test/security/session_wipe_test.dart</name>
  <files>test/security/session_wipe_test.dart</files>
  <action>
In TC-WIPE-002 test case (lines 71-122):

Current: Creates fake docs in `rsa_key_transfers` collection with `fromUserId` / `toUserId` fields
Action:
1. Replace the collection name from `rsa_key_transfers` to `handshakes`
2. Replace field names:
   - `fromUserId` → remove (not used in new model; auth provides this context)
   - `toUserId` → `senderId`
3. Keep the test logic of creating multiple docs and verifying batch delete works
4. Update the test description/comments to reference "handshakes" instead of "rsa_key_transfers"
5. Update the print/reason strings from "rsa_key_transfers" to "handshakes"

Keep: The underlying test logic (batch create → batch delete verification) is valid; only the collection/field names change.
  </action>
  <verify>
grep -n "rsa_key_transfers" test/security/session_wipe_test.dart | wc -l
# Should return 0 after cleanup
flutter test test/security/session_wipe_test.dart::TC-WIPE-002 -v
# Test should pass with renamed collections
  </verify>
  <done>TC-WIPE-002 test refactored to use handshakes collection with senderId/receiverId fields; test still verifies batch-delete logic</done>
</task>

<task type="auto">
  <name>Task 3: Remove stale comments and documentationreferences from key_repository.dart</name>
  <files>lib/data/repositories/key_repository.dart</files>
  <action>
Scan key_repository.dart for any comments or documentation mentioning the old `rsa_key_transfers` model or outdated field patterns.

Current file structure:
- Lines 1-50: Imports + basic accessors
- Lines 178-226: "RSA public key sharing" section (uses new `handshakes` collection — keep as-is)
- Lines 391-428: "Session key management" (references `handshakes` — keep as-is)
- Lines 430-544: "Receiver-Authorized Handshake" (new auto-ID pattern — keep as-is)

Action: Verify NO stale comments mention:
- `rsa_key_transfers` (deprecated collection)
- Old `fromUserId`/`toUserId` patterns
- References to "deterministic" outside the neutral_handshakes context

If found, remove or update to reflect the current auto-ID model. If none found, no changes needed.
  </action>
  <verify>
grep -i "rsa_key_transfer\|fromUserId.*firestore\|toUserId.*firestore" lib/data/repositories/key_repository.dart
# Should return 0 matches (parameter names toUserId are OK; Firestore field uses are not)
  </verify>
  <done>key_repository.dart verified clean; no stale references to old model; all Firestore operations use senderId/receiverId</done>
</task>

<task type="auto">
  <name>Task 4: Verify handshake_repository.dart deterministic pattern is intentional and keep it</name>
  <files>lib/data/repositories/handshake_repository.dart</files>
  <action>
Review handshake_repository.dart (neutral_handshakes layer):
- Lines 9-13: Class docstring mentions "deterministic doc IDs (`${proposerId}_${partnerId}`)"
- Lines 30-35: sendProposal() docstring mentions "deterministic doc ID"
- Lines 218-232: streamHandshakeWithUser() docstring mentions both directional docs

Action: NO CHANGES — this is the intentional design for connection-layer proposals.
These deterministic IDs are correct and necessary for:
1. Idempotent re-sends (same doc ID on retry)
2. Querying both directions (A→B and B→A)
3. Atomic acceptance via transaction

Keep all comments and logic as-is. Document this decision by adding a comment block at the top of the class if not already present:

```dart
/// Manages neutral handshake proposals for the connection-layer.
///
/// DESIGN: Uses deterministic doc IDs (`${proposerId}_${partnerId}`) to ensure
/// idempotent re-sends and symmetric mutual-acceptance (both A→B and B→A docs
/// can exist). This is intentional and distinct from the handshakes collection
/// (auto-ID) which uses asymmetric senderId/receiverId roles.
```

Verify the comment explains the distinction between:
- `neutral_handshakes` (deterministic, symmetric proposals)
- `handshakes` (auto-ID, asymmetric role assignment)
  </action>
  <verify>
grep -n "deterministic" lib/data/repositories/handshake_repository.dart
# Should show 2-3 matches explaining the design choice
grep -n "neutral_handshakes" lib/data/repositories/handshake_repository.dart
# Should show references confirming this is for connection layer, not transfers
  </verify>
  <done>handshake_repository.dart reviewed and confirmed: deterministic pattern is intentional; class docstring distinguishes from auto-ID handshakes; no changes required</done>
</task>

<task type="auto">
  <name>Task 5: Update audit report references to match cleaned test cases</name>
  <files>scripts/security_audit_report.dart, scripts/write_obsidian_report.dart</files>
  <action>
In scripts/security_audit_report.dart and scripts/write_obsidian_report.dart:

Search for references to "rsa_key_transfers" in test case descriptions or table rows.

Current text (around line 57 in security_audit_report.dart):
```
| TC-WIPE-002 | rsa_key_transfers purged | Run: flutter test test/security/session_wipe_test.dart |
```

Update to:
```
| TC-WIPE-002 | handshakes purged | Run: flutter test test/security/session_wipe_test.dart |
```

Also check write_obsidian_report.dart around line 194 for similar references and update.
  </action>
  <verify>
grep "rsa_key_transfers" scripts/security_audit_report.dart scripts/write_obsidian_report.dart
# Should return 0 matches after cleanup
flutter test test/security/session_wipe_test.dart -v
# Full test suite should still pass
  </verify>
  <done>Audit report descriptions updated to reference handshakes instead of rsa_key_transfers; reports are in sync with actual test implementations</done>
</task>

<task type="auto">
  <name>Task 6: Final verification and test execution</name>
  <files>none (verification only)</files>
  <action>
Run full test suite to ensure no cleanup broke anything:

```bash
flutter test test/security/session_wipe_test.dart -v
flutter test test/handshake/ -v
flutter analyze
```

Verify:
1. Session wipe tests pass (TC-WIPE-001 through TC-WIPE-006)
2. Handshake tests pass (neutral_handshakes + auto-ID patterns)
3. No analyzer warnings introduced
4. No references to rsa_key_transfers in codebase (final grep)
  </action>
  <verify>
flutter test test/security/session_wipe_test.dart -v | grep -E "PASSED|FAILED"
flutter test test/handshake/handshake_repository_test.dart -v | grep -E "PASSED|FAILED"
flutter analyze | grep -i error
grep -r "rsa_key_transfers" lib/ test/ scripts/ | wc -l
# Should return 0
  </verify>
  <done>All tests passing; flutter analyze clean; no rsa_key_transfers references remain; codebase unified on auto-ID (handshakes) and neutral proposals (deterministic)</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Handshake Collection | Auto-ID docs with senderId/receiverId (asymmetric role assignment); input validation required on role queries |
| Neutral Handshakes | Deterministic doc IDs (symmetric proposals); client-computed IDs used as keys |
| Firestore Security Rules | Must reject rsa_key_transfers writes (no longer used) if any persist |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-260526-01 | T (Tampering) | Stale field references in queries | mitigate | Remove toUserId/fromUserId Firestore field operations; keep only in method params. Verify no orphaned where() clauses on old fields. |
| T-260526-02 | R (Repudiation) | Test fixtures referencing old model | mitigate | Update TC-WIPE-002 to use handshakes collection; ensures tests verify current code paths, not deprecated ones. |
| T-260526-03 | I (Information Disclosure) | Misleading comments about architecture | mitigate | Update handshake_repository.dart docstring to clarify deterministic vs. auto-ID distinction; aids future maintainers. |
</threat_model>

<verification>
## Post-Cleanup Verification

1. **No rsa_key_transfers references:**
   ```bash
   grep -r "rsa_key_transfers" lib/ test/ scripts/ || echo "✅ CLEAN"
   ```

2. **Test suite passes:**
   ```bash
   flutter test test/security/session_wipe_test.dart::TC-WIPE-002 -v
   flutter test test/handshake/ -v
   ```

3. **Analyzer clean:**
   ```bash
   flutter analyze | grep -i error || echo "✅ NO ERRORS"
   ```

4. **Auto-ID handshakes verified:**
   ```bash
   grep -c "collection(FirebaseConstants.handshakes)" lib/data/repositories/key_repository.dart
   # Should show 4+ (selectSenderHandshake, getPublicKeyFor, getSentKeyTransfers, getReceivedKeys, etc.)
   ```

5. **Neutral handshakes with deterministic IDs verified:**
   ```bash
   grep -c "\\\$.*proposerId.*\\\$.*partnerId" lib/data/repositories/handshake_repository.dart
   # Should show 3+ (doc ID construction in sendProposal, acceptProposal, streamHandshakeWithUser)
   ```
</verification>

<success_criteria>
- No references to `rsa_key_transfers` collection in lib/, test/, or scripts/
- No Firestore query operations using `fromUserId` or `toUserId` as field names (method params OK)
- TC-WIPE-002 test updated to use `handshakes` collection; test still passes
- handshake_repository.dart comments clarify deterministic vs. auto-ID distinction
- security_audit_report.dart and write_obsidian_report.dart updated with new test descriptions
- `flutter test test/security/session_wipe_test.dart` passes all 6 cases
- `flutter test test/handshake/` passes all handshake tests
- `flutter analyze` reports no errors or warnings
</success_criteria>

<output>
After completion, create `.planning/quick/260526-sxe-remove-unused-deterministic-id-implement/260526-sxe-SUMMARY.md`

Commit: `refactor: remove unused rsa_key_transfers references and clean up deprecated ID patterns` + co-author
</output>
