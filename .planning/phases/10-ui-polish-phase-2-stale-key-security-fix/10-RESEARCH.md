# Phase 10: UI Polish Phase 2 + Stale-Key Security Fix — Research

**Researched:** 2026-05-31
**Domain:** Flutter UI polish (glassmorphic dialogs), Dart security regression fix
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Security Fix (D-01 – D-03)**
- **D-01:** Restore the `previousPublicKey` capture immediately before the `setState` block in `_onHandshakeUpdate` (line ~207 in the reference commit `793e226`). Capture as `final previousPublicKey = _selectedReceiverPublicKeyJson;`.
- **D-02:** After `setState`, apply the D-06 mid-flight guard (`if (_encrypting || _encryptingKey) return;`) before the stale-key check.
- **D-03:** Stale-key check condition: `if (previousPublicKey != null && publicKey != previousPublicKey && _encryptedAESKey != null)` → call `_wipeSensitiveData()` + SnackBar `'Receiver key changed — re-encrypt required.'`. Do NOT call `_revertToWaiting()` — preserve `_receiverId`, `_receiverUsername`, `_selectedReceiverPublicKeyJson` (file + receiver preserved, only encrypted state wiped).

**UI Polish — Dialog Styling (D-04 – D-06)**
- **D-04:** All `AlertDialog` instances that currently use the plain Material design get the glassmorphic treatment: `backgroundColor: Colors.transparent`, `elevation: 0`, `insetPadding: EdgeInsets.all(24)`, content wrapped in `GlassContainer(padding: EdgeInsets.all(24), borderRadius: 28)`.
- **D-05:** Confirm/destructive actions inside dialogs use `CrypButton` (not `FilledButton` or `TextButton` for the primary action). Cancel actions remain `TextButton`. Buttons laid out in a `Row` with `Expanded` children.
- **D-06:** Icons added to dialogs: context-appropriate icon (48px) above the title.

**Admin Dashboard Visual Identity (D-07)**
- **D-07:** Commit the completed 260531-a1k changes as-is.

**Housekeeping**
- **D-08:** Commit `ROADMAP.md` working-tree changes.
- **D-09:** No new Firestore rules, no schema changes, no new collections needed.

### Claude's Discretion
- Exact ordering of commits (atomic vs batched)
- Whether to run `flutter test` in Wave 1 or only in Wave 2 final gate
- Minor wording tweaks inside dialog text (keep intent, not verbatim)

### Deferred Ideas (OUT OF SCOPE)
- Typography extraction to theme
- Glass opacity standardization
- Session state color migration
- Face ID re-enable (`biometric_helper.dart`)
</user_constraints>

---

## Summary

Phase 10 is a dual-workstream phase with no new features. The two workstreams are strictly parallel — they touch different methods and different screens, making them safe to plan as independent wave-1 tasks.

**Workstream 1 — Security regression fix:** Commit `580616d` (WIP, post-Phase-09 fix) dropped exactly 3 lines from `SenderScreen._onHandshakeUpdate`: the `final previousPublicKey = _selectedReceiverPublicKeyJson;` capture, the `if (_encrypting || _encryptingKey) return;` mid-flight guard, and the `if (previousPublicKey != null && publicKey != previousPublicKey && _encryptedAESKey != null)` stale-key invalidation block. These lines were verified present and correct at commit `793e226` (Phase-09 Phase 09-03 feature commit). The fix is surgical: insert those 3 blocks back into the existing non-empty branch of `_onHandshakeUpdate` at the exact location described in D-01/D-02/D-03. The existing test suite (`test/sender/stale_key_test.dart` GAP2-01, GAP2-02) exercises the logic model and passes.

**Workstream 2 — UI polish finalization:** All 7 dialog instances across 6 screens already have the glassmorphic pattern in the working tree (transparent AlertDialog + GlassContainer + CrypButton). The working tree also has all 4 admin dashboard changes from quick task 260531-a1k. The planner's work is to verify spacing consistency (see the UI-SPEC discrepancy below), run `flutter analyze`, and commit. No new UI coding is required — this is a finalize-and-commit task.

**Primary recommendation:** 10-01-PLAN.md (stale-key restore) and 10-02-PLAN.md (UI finalization + housekeeping) execute in parallel. The stale-key fix is 5 lines of Dart; the UI finalization is a spacing audit + commit. Both gates are `flutter analyze` clean + 113/114 tests passing.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Stale AES key invalidation | Frontend presentation (SenderScreen) | — | Logic lives in the stream callback `_onHandshakeUpdate`; no backend change needed |
| Glassmorphic dialog styling | Frontend presentation | — | Pure UI change to `showDialog` call sites; no data or service layer involvement |
| Admin dashboard visual identity | Frontend presentation (admin/) | — | AppBar title + widget wrapping; no data layer |
| ROADMAP/STATE housekeeping | Planning artifacts | — | Markdown file commits; no code |

---

## Standard Stack

### Core (in use — no new additions)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter/material | SDK | Material 3 widgets including `AlertDialog`, `SnackBar` | Project baseline |
| `GlassContainer` | project-local | Glassmorphic container (BackdropFilter + blur) | Defined in `lib/presentation/widgets/shared_widgets.dart` |
| `CrypButton` | project-local | 3D haptic button with session-state awareness | Defined in `lib/presentation/widgets/shared_widgets.dart` |
| `google_fonts` | existing dep | Orbitron + Exo2 for admin dashboard | Already imported in admin screens |

**Installation:** No new packages. All required widgets exist in the project. [VERIFIED: working tree imports]

---

## Architecture Patterns

### System Architecture Diagram

```
Working tree (modified files)
        │
        ├── lib/presentation/sender/sender_screen.dart
        │       └── _onHandshakeUpdate()
        │               ├── [MISSING] previousPublicKey capture     ← D-01 restore
        │               ├── [MISSING] mid-flight guard              ← D-02 restore
        │               └── [MISSING] stale-key invalidation block  ← D-03 restore
        │
        ├── lib/presentation/home/find_friends_screen.dart          ← glassmorphic DONE
        ├── lib/presentation/home/home_screen.dart                   ← glassmorphic DONE
        ├── lib/presentation/receiver/decrypt_screen.dart            ← glassmorphic DONE
        ├── lib/presentation/receiver/receiver_transfer_screen.dart  ← glassmorphic DONE
        ├── lib/presentation/sender/sender_screen.dart               ← glassmorphic DONE
        ├── lib/presentation/sender/transfer_progress_screen.dart    ← glassmorphic DONE
        │
        ├── lib/presentation/admin/admin_dashboard.dart              ← 260531-a1k DONE
        ├── lib/presentation/admin/admin_dashboard_screen.dart       ← 260531-a1k DONE
        ├── lib/presentation/admin/widgets/connection_node_map.dart  ← 260531-a1k DONE
        └── lib/presentation/admin/widgets/security_pulse_feed.dart  ← 260531-a1k DONE
```

### Component Responsibilities

| Component | Responsibility in Phase 10 |
|-----------|---------------------------|
| `SenderScreen._onHandshakeUpdate` | Restore 3 dropped lines (D-01/D-02/D-03) |
| `SenderScreen._wipeSensitiveData()` | Called by restored guard — clears `_aesKey`, `_iv`, `_encryptedBytes`, `_encryptedAESKey`; does NOT clear receiver identity fields |
| `AlertDialog` (6 screens) | Verify all 7 instances match canonical glassmorphic structure; commit |
| Admin dashboard files (4) | Commit as-is; already complete per 260531-a1k-SUMMARY.md |
| `ROADMAP.md` | Commit Phase 999.1 deferral + Phase 08 completion (D-08) |

### Stale-Key Guard: Exact Code to Restore

The exact block to insert in `_onHandshakeUpdate`, in the non-empty branch after the `_handshakeDocId` assignment and before `final isReconnect`:

```dart
// Source: git show 793e226:lib/presentation/sender/sender_screen.dart lines 206-230
// D-05: capture old key BEFORE setState so the comparison is against the previous value
final previousPublicKey = _selectedReceiverPublicKeyJson;
setState(() {
  _receiverId = receiverId;
  _receiverUsername = receiverUsername;
  _selectedReceiverPublicKeyJson = publicKey;
});
_streamSettled = true;
_everConnected = true;
_checkTofuStatus(receiverId, publicKey);

// D-06: mid-flight guard — skip stale check and receiverReady logic if encryption is in flight
if (_encrypting || _encryptingKey) return;

// D-05: stale AES key invalidation — key changed while encrypted AES key exists
if (previousPublicKey != null &&
    publicKey != previousPublicKey &&
    _encryptedAESKey != null) {
  _wipeSensitiveData();
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Receiver key changed — re-encrypt required.')),
    );
  }
}
```

**IMPORTANT:** The current working tree also has an `isReconnect` block and an `_everConnected` assignment that were added in `580616d`. These are valid additions that must be preserved. The stale-key guard must be inserted alongside them — not replacing them.

### Current Working Tree State (Exact)

The current `_onHandshakeUpdate` non-empty branch (lines 203-247 in working tree) has:
1. `final isReconnect = _everConnected && _selectedReceiverPublicKeyJson == null;` — NEW (from 580616d) — KEEP
2. `setState(...)` — present, but WITHOUT the `previousPublicKey` capture before it
3. `_streamSettled = true;` — present
4. `_everConnected = true;` — NEW (from 580616d) — KEEP
5. `_checkTofuStatus(...)` — present
6. `if (isReconnect && mounted)` SnackBar block — NEW (from 580616d) — KEEP
7. `receiverReady` parsing + `_onReceiverBecameReady()` block — present
8. **MISSING:** `previousPublicKey` capture before setState
9. **MISSING:** `if (_encrypting || _encryptingKey) return;` guard after setState/checkTofu
10. **MISSING:** stale-key invalidation if-block

The insertion point for D-01 is: immediately before the `final isReconnect = ...` line.
The insertion point for D-02 and D-03 is: after `_checkTofuStatus(...)` + `if (isReconnect...) SnackBar` block, before the `receiverReady` parsing line.

### Canonical Glassmorphic Dialog Pattern

```dart
// Source: working tree lib/presentation/home/find_friends_screen.dart (reference)
AlertDialog(
  backgroundColor: Colors.transparent,
  elevation: 0,
  insetPadding: const EdgeInsets.all(24),
  content: GlassContainer(
    padding: const EdgeInsets.all(24),
    borderRadius: 28,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon({context_icon}, size: 48, color: {semantic_color}),
        const SizedBox(height: 16),
        Text(title, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),  // NOTE: see spacing discrepancy below
        Text(body, textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 28),  // NOTE: see spacing discrepancy below
        Row(children: [
          Expanded(child: TextButton('Cancel', () => Navigator.pop(ctx, false))),
          const SizedBox(width: 12),  // NOTE: see spacing discrepancy below
          Expanded(child: CrypButton(label: Text(action), color: semantic, ...)),
        ]),
      ],
    ),
  ),
)
```

### Anti-Patterns to Avoid

- **`_revertToWaiting()` in stale-key handler:** This would clear `_receiverId`, `_receiverUsername`, `_selectedReceiverPublicKeyJson`, `_file` — wasting the user's work. Only `_wipeSensitiveData()` is correct; it only clears `_aesKey`, `_iv`, `_encryptedBytes`, `_encryptedAESKey`. [VERIFIED: working tree `_wipeSensitiveData()` at line 452]
- **`FilledButton` as primary dialog action:** All confirmed working-tree dialogs use `CrypButton`; do not revert to `FilledButton`.
- **`TextButton` for primary destructive action:** Cancel stays `TextButton`, confirm/destructive must be `CrypButton`.

---

## Critical Finding: Spacing Discrepancy Between Working Tree and UI-SPEC

**[VERIFIED: grep of working tree]**

The UI-SPEC (`10-UI-SPEC.md`) pre-delivery checklist states:
- "Dialog body-to-buttons gap is `SizedBox(height: 32)` in all 7 instances — not 28"
- "Dialog button gap is `SizedBox(width: 8)` in all 7 instances — not 12"

The **working tree** has:
- `SizedBox(height: 28)` (not 32) in 6 of 7 dialog instances
- `SizedBox(width: 12)` (not 8) in 6 of 7 dialog instances

The `home_screen.dart` role conflict dialog uses `SizedBox(height: 28)` with a single-button layout (no row), which is exempt from the width constraint.

**Affected instances with wrong spacing:**
| File | height gap | width gap |
|------|-----------|----------|
| `find_friends_screen.dart` (line 209) | 28 (needs 32) | 12 (needs 8) |
| `find_friends_screen.dart` (line 710) | 28 (needs 32) | 12 (needs 8) |
| `sender_screen.dart` (line 685) | 28 (needs 32) | 12 (needs 8) |
| `decrypt_screen.dart` (line 151) | 28 (needs 32) | 12 (needs 8) |
| `receiver_transfer_screen.dart` (line 167) | 28 (needs 32) | 12 (needs 8) |
| `transfer_progress_screen.dart` (line 270) | 28 (needs 32) | 12 (needs 8) |
| `home_screen.dart` (line 122) | 28 (needs 32 per spec) | N/A — single button |

The UI-SPEC was produced by `gsd-ui-researcher` + `gsd-ui-checker` and is marked "approved". The checklist explicitly flags these values as requirements. The planner must include spacing corrections in 10-02-PLAN.md.

**Action for planner:** 10-02-PLAN.md must include a spacing correction task that changes all `SizedBox(height: 28)` → `SizedBox(height: 32)` and `SizedBox(width: 12)` → `SizedBox(width: 8)` in the 7 dialog instances inside affected files.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Glassmorphic blur container | Custom BackdropFilter + ClipRRect | `GlassContainer` from `shared_widgets.dart` | Already implemented; consistent blur sigma (24,24) and border tokens |
| 3D haptic button | Custom InkWell + gesture detector | `CrypButton` from `shared_widgets.dart` | Already handles `_isPressed` state, `HapticFeedback.lightImpact()`, `Matrix4` transform |
| Stale-key AES invalidation | New custom state machine | Restore the 3 dropped lines from `793e226` | The logic is already tested (GAP2-01, GAP2-02) and verified; no redesign needed |

---

## Common Pitfalls

### Pitfall 1: Overwriting the `isReconnect` Addition
**What goes wrong:** Restoring the stale-key guard by replacing the entire `else` branch with the 793e226 version would erase the `_everConnected` flag and `isReconnect` SnackBar that `580616d` added.
**Why it happens:** Copy-pasting the reference commit wholesale without reviewing what 580616d added.
**How to avoid:** Insert the 3 missing code fragments surgically at the correct positions; do not replace the entire `if (publicKey != null ...)` block.
**Warning signs:** If `_everConnected` no longer appears in `_onHandshakeUpdate` after the fix, the insertion was too broad.

### Pitfall 2: Placing `previousPublicKey` After `setState`
**What goes wrong:** If `previousPublicKey` is captured after `setState`, it always equals the new `publicKey`, so the stale check never fires.
**Why it happens:** Moving the line slightly after the setState block during formatting.
**How to avoid:** The capture must be `final previousPublicKey = _selectedReceiverPublicKeyJson;` immediately before the `setState(...)` call.

### Pitfall 3: Placing Mid-Flight Guard Before `_checkTofuStatus`
**What goes wrong:** If `if (_encrypting || _encryptingKey) return;` is placed before `_checkTofuStatus(receiverId, publicKey)`, the TOFU fingerprint check is skipped during encryption, which may interfere with trust-on-first-use display.
**Why it happens:** Inserting the guard at the earliest possible position.
**How to avoid:** The guard must come after `_checkTofuStatus(...)` and after the `isReconnect` SnackBar block. [VERIFIED: reference commit 793e226 line 216]

### Pitfall 4: Spacing Values in Dialog Body
**What goes wrong:** Committing the working tree dialogs with `height: 28` / `width: 12` would leave the UI-SPEC pre-delivery checklist failing.
**Why it happens:** The working tree was written before the UI-SPEC checker applied the spacing corrections.
**How to avoid:** Correct all 7 instances to `height: 32` (body-to-buttons gap) and `width: 8` (between Cancel and confirm buttons) before committing.

### Pitfall 5: `home_screen.dart` Single-Button Dialog
**What goes wrong:** Applying the two-button Row pattern to the role conflict dialog, which is informational (single OK button).
**Why it happens:** Mechanical pattern application across all dialogs.
**How to avoid:** `home_screen.dart` role conflict dialog uses `SizedBox(width: double.infinity)` + single `CrypButton` — no Row, no Cancel button. Keep it as-is for the button layout; only fix `height: 28` → `height: 32`.

---

## Test Infrastructure

### Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (Flutter SDK) |
| Config file | none — uses `flutter test` CLI |
| Quick run command | `flutter test test/sender/stale_key_test.dart --no-pub` |
| Full suite command | `flutter test --no-pub` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| D-01/D-02/D-03 | Stale AES key wiped when receiver key changes | unit (logic model) | `flutter test test/sender/stale_key_test.dart --no-pub` | YES — GAP2-01, GAP2-02 |
| D-04/D-05/D-06 | Glassmorphic dialogs in 6 screens | visual/manual | device run | N/A — no widget test |
| D-07 | Admin dashboard visual identity | visual/manual | device run | N/A |
| D-08 | ROADMAP.md committed | git audit | `git log --oneline -3` | N/A |

### Test Baseline [VERIFIED: flutter test --no-pub]
- **113/114 tests passing** (1 known pre-existing failure: `TC010 - Logout clears current user` in `test/module_tests/auth_test.dart`)
- `test/sender/stale_key_test.dart` — 3/3 passing (GAP2-01, GAP2-02, GAP3-02)
- The existing stale-key tests verify the logic model, not the widget. No new test file needed — the existing stubs already cover the D-01/D-02/D-03 behavioral contract.

### Wave 0 Gaps
None — existing test infrastructure covers all phase requirements. The stale-key tests exist and pass at the logic-model level.

---

## Code Examples

### Stale-Key Guard Restore (exact insertion)

The current working tree `_onHandshakeUpdate` non-empty branch starts with:

```dart
// Current working tree (lines ~203-212):
final isReconnect = _everConnected && _selectedReceiverPublicKeyJson == null;
setState(() {
  _receiverId = receiverId;
  _receiverUsername = receiverUsername;
  _selectedReceiverPublicKeyJson = publicKey;
});
_streamSettled = true;
_everConnected = true;
_checkTofuStatus(receiverId, publicKey);
```

**After D-01/D-02/D-03 restore:**

```dart
// Source: git show 793e226 + 580616d combined
// D-01: capture old key BEFORE setState
final previousPublicKey = _selectedReceiverPublicKeyJson;
final isReconnect = _everConnected && _selectedReceiverPublicKeyJson == null;
setState(() {
  _receiverId = receiverId;
  _receiverUsername = receiverUsername;
  _selectedReceiverPublicKeyJson = publicKey;
});
_streamSettled = true;
_everConnected = true;
_checkTofuStatus(receiverId, publicKey);

if (isReconnect && mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Connection re-established with @$receiverUsername — new RSA key received.'),
      backgroundColor: Theme.of(context).colorScheme.secondary,
      duration: const Duration(seconds: 4),
    ),
  );
}

// D-02: mid-flight guard
if (_encrypting || _encryptingKey) return;

// D-03: stale AES key invalidation
if (previousPublicKey != null &&
    publicKey != previousPublicKey &&
    _encryptedAESKey != null) {
  _wipeSensitiveData();
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Receiver key changed — re-encrypt required.')),
    );
  }
}

// Parse receiverReady from handshake doc ...
```

### Canonical Glassmorphic Dialog (corrected spacing)

```dart
// Source: 10-UI-SPEC.md canonical structure + spacing corrections
AlertDialog(
  backgroundColor: Colors.transparent,
  elevation: 0,
  insetPadding: const EdgeInsets.all(24),
  content: GlassContainer(
    padding: const EdgeInsets.all(24),
    borderRadius: 28,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.warning_rounded, size: 48, color: cs.error),
        const SizedBox(height: 16),   // icon → title: 16px
        Text('Abort Transfer?',
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),   // title → body: 12px (working tree value; NOT 8)
        Text('...body...', textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 32),   // body → buttons: 32px (was 28 — must fix)
        Row(children: [
          Expanded(child: TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'))),
          const SizedBox(width: 8),   // button gap: 8px (was 12 — must fix)
          Expanded(child: CrypButton(
              label: const Text('Abort & Destroy'),
              color: cs.error,
              onPressed: () => Navigator.pop(ctx, true))),
        ]),
      ],
    ),
  ),
)
```

---

## Runtime State Inventory

Phase 10 is a code-only change (no renames, no Firestore schema changes). Runtime state inventory not applicable.

Step 2.5: SKIPPED — no rename/refactor scope.

---

## Environment Availability

Step 2.6: All required tools are in-project Flutter dependencies. No external services beyond the existing project baseline.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | All Dart/Flutter work | Yes | detected in project | — |
| `flutter analyze` | Quality gate | Yes | via Flutter SDK | — |
| `flutter test` | Test gate | Yes | via Flutter SDK | — |

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test |
| Config file | none |
| Quick run command | `flutter test test/sender/stale_key_test.dart --no-pub` |
| Full suite command | `flutter test --no-pub` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| D-01 | previousPublicKey captured before setState | unit (logic model) | `flutter test test/sender/stale_key_test.dart --no-pub` | YES — GAP2-01 |
| D-02 | Mid-flight guard blocks stale check | unit (logic model) | `flutter test test/sender/stale_key_test.dart --no-pub` | YES — GAP2-02 |
| D-03 | Stale AES key wiped on key change | unit (logic model) | `flutter test test/sender/stale_key_test.dart --no-pub` | YES — GAP2-01 |
| D-04/05/06 | Glassmorphic dialog rendering | manual | device run | Not automated |

### Sampling Rate
- **Per task commit:** `flutter test test/sender/stale_key_test.dart --no-pub`
- **Per wave merge:** `flutter test --no-pub`
- **Phase gate:** Full suite green (`113+/114`) before `/gsd-verify-work`

### Wave 0 Gaps
None — existing test infrastructure covers all phase requirements.

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | yes | Stale-key guard prevents AES key computed to stale receiver RSA key — core session integrity fix |
| V4 Access Control | no | — |
| V5 Input Validation | no | — |
| V6 Cryptography | yes | `_wipeSensitiveData()` zeros `Uint8List` buffers — memory security pattern |

### Known Threat Pattern: Stale RSA Key Encryption

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Sender encrypts AES key to outdated receiver RSA public key after receiver re-generated keypair | Spoofing (encrypted data unreadable by intended receiver) | Capture `previousPublicKey` before setState; compare after setState; call `_wipeSensitiveData()` if changed + `_encryptedAESKey != null` |

**Security impact of regression:** If a receiver closes and reopens their mailbox (regenerating their RSA keypair), the stream update in `_onHandshakeUpdate` would update `_selectedReceiverPublicKeyJson` to the new key, but `_encryptedAESKey` — already encrypted to the **old** key — would remain. The sender would then upload an AES key that the receiver cannot decrypt, causing a silent transfer failure with no user notification. The restored guard catches this and forces re-encryption.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The `isReconnect` SnackBar block (added in 580616d) should be preserved between the checkTofu call and the mid-flight guard | Code Examples | If wrong, `_onHandshakeUpdate` loses the reconnect notification — low security risk, mild UX regression |

The insertion point for D-02/D-03 (after `isReconnect` SnackBar) is based on reading the working tree source [VERIFIED: `sed -n '200,248p' sender_screen.dart`]. The only ambiguity is the exact ordering of the isReconnect SnackBar relative to the mid-flight guard — the reference commit 793e226 did not have the isReconnect block, so the ordering between them is a new decision.

**Recommendation for A1:** Place mid-flight guard AFTER the isReconnect SnackBar. The SnackBar is informational (not security-sensitive) and should fire even during encryption. The stale-key check (which calls `_wipeSensitiveData()`) must not fire during encryption — hence the guard before it.

---

## Open Questions

1. **Spacing: working tree (28/12) vs. UI-SPEC (32/8)**
   - What we know: Working tree has `height: 28` and `width: 12`; UI-SPEC checklist requires `height: 32` and `width: 8`.
   - What's unclear: Whether the checker approved the spec knowing the working tree had 28/12 (i.e., spec is aspirational and corrections are expected in this phase) or whether it was a documentation error.
   - Recommendation: Apply the UI-SPEC values (32/8) as required by the checker sign-off. The UI-SPEC explicitly calls these out in the pre-delivery checklist. The planner should include a spacing correction step in 10-02-PLAN.md.

---

## Sources

### Primary (HIGH confidence)
- `git show 793e226:lib/presentation/sender/sender_screen.dart` — exact reference implementation of D-01/D-02/D-03 (lines 207-230)
- `git diff HEAD -- lib/presentation/sender/sender_screen.dart` — confirmed 3 blocks absent from working tree
- `git diff HEAD -- lib/presentation/` (all 10 affected files) — confirmed glassmorphic pattern present in all dialog instances
- `test/sender/stale_key_test.dart` — GAP2-01/GAP2-02 pass in working tree
- `.planning/phases/10-ui-polish-phase-2-stale-key-security-fix/10-UI-SPEC.md` — canonical dialog structure, spacing contract
- `.planning/quick/260531-a1k-admin-dashboard-ui-consistency/260531-a1k-SUMMARY.md` — admin dashboard 4/4 tasks confirmed complete
- `flutter analyze lib/presentation/` — No issues found (working tree)
- `flutter test --no-pub` — 113/114 passing (1 pre-existing failure: TC010)

### Secondary (MEDIUM confidence)
- `git diff 793e226..580616d -- lib/presentation/sender/sender_screen.dart` — confirmed dropped lines in WIP commit

---

## Metadata

**Confidence breakdown:**
- Security fix scope: HIGH — exact diff verified against reference commit and working tree
- UI polish scope: HIGH — all working tree diffs reviewed; all 7 dialog instances confirmed glassmorphic
- Spacing discrepancy: HIGH — verified by grep across all 6 files; UI-SPEC values confirmed
- Test baseline: HIGH — flutter test run confirms 113/114

**Research date:** 2026-05-31
**Valid until:** 2026-06-14 (30 days — stable codebase, no fast-moving dependencies)
