# SessionManager Mid-Decrypt Lifecycle Gap — Close & Verify

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify the `ReceiverTransferScreen`/`DecryptScreen` `SessionManager` propagation gap is fully closed, add the one missing regression test, and update the Known Open Issues in CLAUDE.md.

**Architecture:** The documented gap stated that `ReceiverTransferScreen` had no `SessionManager` observer. Code inspection confirms both `ReceiverTransferScreen` and `DecryptScreen` already receive `sessionManager` as a required constructor arg and wire `stateNotifier.addListener` in `initState`. The remaining work is: (1) add TC-WIPE-008 to verify the listener-callback path that the screens depend on, and (2) close the stale documentation entry.

**Tech Stack:** Dart, Flutter, `flutter_test`, `SessionManager` (lib/core/utils/session_manager.dart)

## Global Constraints

- `flutter analyze` must return **No issues found** after every task.
- No new dependencies.
- Tests use the existing pattern in `test/security/session_wipe_test.dart` — no `FakeFirebaseFirestore` or Firebase mocks needed for these pure `SessionManager` unit tests.
- Commit messages follow the existing convention: `test(security): ...` / `docs: ...`

---

### Task 1: Add TC-WIPE-008 — verify `stateNotifier.addListener` callback fires on `wipeSession()`

**Why this test matters:** `ReceiverTransferScreen._onSessionStateChanged` (line 99 of `receiver_transfer_screen.dart`) and `DecryptScreen._onSessionTerminated` (line 86 of `decrypt_screen.dart`) both register via `widget.sessionManager.stateNotifier.addListener(...)`. TC-WIPE-007 already verifies `stateNotifier.value` is set correctly; TC-WIPE-008 verifies the listener *callback* fires — the exact path the screens use to react to termination.

**Files:**
- Modify: `test/security/session_wipe_test.dart` (append TC-WIPE-008 inside the existing `group`)

**Interfaces:**
- Consumes: `SessionManager` from `package:cryptransfer/core/utils/session_manager.dart`
- Produces: TC-WIPE-008 test case that asserts `stateNotifier.addListener` callback fires when `wipeSession()` is called, then is silent after `removeListener`

- [ ] **Step 1: Locate the insertion point in session_wipe_test.dart**

Open `test/security/session_wipe_test.dart`. Find the closing `});` of the last test (TC-WIPE-007, around line 308). The new test goes **before** the outer `group` closing `});`.

The file ends with:
```dart
        // ignore: avoid_print
        print('✅ TC-WIPE-007 PASSED: wipeSession() transitions to terminated; '
            '_cancelled flag logic confirmed; idempotent');
      },
    );
  });         // ← outer group closes here
}
```

- [ ] **Step 2: Add TC-WIPE-008**

Insert the following test between TC-WIPE-007's closing `);` and the outer `group` closing `});`:

```dart
    // ─── TC-WIPE-008 ─────────────────────────────────────────────────────────
    //
    // Verifies that stateNotifier.addListener() callbacks fire when
    // wipeSession() transitions to terminated.  This mirrors the exact
    // listener pattern used by ReceiverTransferScreen (line 99) and
    // DecryptScreen (line 86) — if this mechanism regresses, both screens
    // lose their kill-switch reaction.
    test(
      'TC-WIPE-008: stateNotifier.addListener callback fires on wipeSession() '
      'and is silent after removeListener (screens listener pattern)',
      () {
        final manager = SessionManager();

        // Mirror what ReceiverTransferScreen.initState() does:
        //   widget.sessionManager.stateNotifier.addListener(_onSessionStateChanged)
        SessionState? receivedState;
        void listener() => receivedState = manager.stateNotifier.value;

        manager.stateNotifier.addListener(listener);

        // Call wipeSession() — this is what ReceiverScreen.PopScope triggers.
        manager.wipeSession(onBuffersWipe: () {});

        expect(
          receivedState,
          SessionState.terminated,
          reason:
              'TC-WIPE-008: stateNotifier listener must receive terminated '
              'when wipeSession() is called (ReceiverTransferScreen/DecryptScreen '
              'kill-switch path)',
        );

        // Mirror what ReceiverTransferScreen.dispose() does:
        //   widget.sessionManager.stateNotifier.removeListener(_onSessionStateChanged)
        // After removeListener, a second transition must NOT fire the callback.
        receivedState = null;
        manager.stateNotifier.removeListener(listener);

        // Create a fresh manager so we can call wipeSession again.
        final manager2 = SessionManager();
        manager2.stateNotifier.addListener(listener);
        manager2.stateNotifier.removeListener(listener); // immediately remove
        manager2.wipeSession(onBuffersWipe: () {});

        expect(
          receivedState,
          isNull,
          reason:
              'TC-WIPE-008: listener must NOT fire after removeListener() — '
              'dispose() teardown is clean',
        );

        manager2.dispose();
        manager.dispose();

        // ignore: avoid_print
        print('✅ TC-WIPE-008 PASSED: stateNotifier listener fires on wipeSession(); '
            'removeListener() cleanly prevents further callbacks');
      },
    );
```

- [ ] **Step 3: Run the test to verify it passes**

```
flutter test test/security/session_wipe_test.dart --name "TC-WIPE-008" -v
```

Expected output:
```
✅ TC-WIPE-008 PASSED: stateNotifier listener fires on wipeSession(); removeListener() cleanly prevents further callbacks
  TC-WIPE-008: stateNotifier.addListener callback fires on wipeSession() ... ✓
All tests passed!
```

- [ ] **Step 4: Run the full test suite to confirm no regressions**

```
flutter test --reporter=compact
```

Expected: all tests pass, no failures.

- [ ] **Step 5: Run flutter analyze**

```
flutter analyze
```

Expected: `No issues found.`

- [ ] **Step 6: Commit**

```bash
git add test/security/session_wipe_test.dart
git commit -m "test(security): TC-WIPE-008 — verify stateNotifier.addListener fires on wipeSession()

Regression guard for the ReceiverTransferScreen/DecryptScreen kill-switch
listener path. Mirrors the exact stateNotifier.addListener pattern used in
initState() on both screens so that a future refactor cannot silently break
the terminated-state propagation."
```

---

### Task 2: Close the stale Known Open Issue in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (Known Open Issues section → Completed Features section)

**Interfaces:**
- Consumes: nothing
- Produces: updated CLAUDE.md with the gap marked closed and evidence of when/how it was fixed

- [ ] **Step 1: Locate the Known Open Issue entry**

In `CLAUDE.md`, find the `## 🔲 Known Open Issues` → `### Session Architecture` section containing:

```markdown
- [ ] **`ReceiverTransferScreen` does not propagate `SessionManager`** — navigation is automatic but `ReceiverTransferScreen` creates its own `TransferRepository` without access to the `SessionManager` from `ReceiverScreen`. If the user backgrounds the app mid-decrypt, the `SessionManager.terminated` state is set by `ReceiverScreen.didChangeAppLifecycleState`, but `ReceiverTransferScreen` has no observer. Consider passing `sessionManager` as a constructor arg or using an `InheritedWidget`.
```

- [ ] **Step 2: Remove the entry from Known Open Issues**

Delete the entire `### Session Architecture` block (including the subsection heading) since it will have no remaining items. If there are other items under that heading, only delete the `ReceiverTransferScreen` bullet.

- [ ] **Step 3: Add a Completed Feature entry**

In the `## ✅ Completed Features` section, append the following entry (insert in chronological order after the last `[x]` entry):

```markdown
- [x] **`ReceiverTransferScreen`/`DecryptScreen` kill-switch propagation (2026-06-17)** — Both screens receive `SessionManager` as a required constructor arg; `stateNotifier.addListener` is wired in `initState` and removed in `dispose`. `ReceiverScreen.didChangeAppLifecycleState` intentionally guards with `!_sessionLocked` so the private key survives an active decryption if the user briefly backgrounds the app; the 120 s watchdog timer aborts abandoned sessions. TC-WIPE-008 verifies the listener propagation path.
```

- [ ] **Step 4: Run flutter analyze**

```
flutter analyze
```

Expected: `No issues found.`

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: close stale ReceiverTransferScreen SessionManager gap

The gap was already fixed: sessionManager is a required constructor arg on
both ReceiverTransferScreen and DecryptScreen, with stateNotifier.addListener
wired in initState on each. The _sessionLocked guard in ReceiverScreen is
intentional — private key must survive active decryption. TC-WIPE-008 now
covers the listener path."
```

---

## Self-Review

### Spec Coverage

| Documented gap | Task that addresses it |
|---|---|
| `ReceiverTransferScreen` has no `SessionManager` observer | Verified closed in Task 1 preamble; TC-WIPE-008 is the regression guard |
| CLAUDE.md Known Open Issues still lists the gap | Task 2 closes it |

### Placeholder Scan

No TBDs, no "implement later", no references to functions not defined above.

### Type Consistency

`SessionManager`, `SessionState.terminated`, `stateNotifier`, `wipeSession`, `addListener`, `removeListener` — all names match exactly as they appear in `lib/core/utils/session_manager.dart` (verified against the source).
