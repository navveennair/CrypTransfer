# Phase 02 — UI Review

**Audited:** 2026-04-22
**Baseline:** Abstract 6-pillar standards (no UI-SPEC.md present); GitHub Dark design system (darkBg #090C10, darkSurface #10141B, primary #58A6FF, Material 3)
**Screenshots:** Not captured (no dev server detected on ports 3000, 5173, or 8080)

---

## Pillar Scores

| Pillar | Score | Key Finding |
|--------|-------|-------------|
| 1. Copywriting | 3/4 | Copy is specific and domain-appropriate; emoji in step labels is inconsistent with the security-app register |
| 2. Visuals | 3/4 | Strong animated hierarchy and 3D CrypButton system; ReceiverTransferScreen title duplicates its AppBar label |
| 3. Color | 3/4 | Theme tokens used correctly; 31 raw `Colors.*` calls in receiver screens break the token contract |
| 4. Typography | 3/4 | Two fonts (Inter body / Poppins headings) applied consistently; 7 raw font sizes bypass the theme text scale |
| 5. Spacing | 4/4 | Spacing is systematic and consistent across all receiver/sender screens |
| 6. Experience Design | 4/4 | Loading, error, empty, disabled, and kill-switch states are all fully handled |

**Overall: 20/24**

---

## Top 3 Priority Fixes

1. **Emoji in `_StatusStep` labels** — Undermines the serious security-app tone and will render inconsistently across Android OEM emoji fonts. Replace `'📡  Establishing secure connection…'`, `'🔐  Verifying encryption parameters…'`, and `'✅  Ready to decrypt'` with icon widgets placed in the existing `indicator` slot of `_StepTile`, matching the approach already used for the done/active/pending states. (`receiver_transfer_screen.dart` lines 69-71; `download_confirm_screen.dart` line 365)

2. **Raw `Colors.*` calls instead of `ColorScheme` tokens** — 31 occurrences in the receiver files alone (e.g., `Colors.green`, `Colors.amber`, `Colors.orange`, `Colors.indigo`) hardcode values that diverge from the GitHub Dark palette and will not adapt if the theme seed changes. Replace with `cs.primary`, `cs.secondary`, `cs.tertiary`, `cs.error`, or named AppTheme constants. High-value targets: `StepCard` done-state border (`Colors.green.shade400`), `_FindSenderSheet` Friend label (`Colors.green`), `_ConnectedBadge` in sender screen (all `Colors.green`).

3. **"Incoming File" title duplicated on ReceiverTransferScreen** — The `AppBar.title` reads `'Incoming File'` (line 186) and the first `Text` widget in the body also reads `'Incoming File'` (line 219-223), creating visual redundancy and wasting 88px of prime vertical real estate that is then immediately re-stated. Change the body heading to show the actual filename (`widget.fileName`) and reserve the AppBar label as the screen name only.

---

## Detailed Findings

### Pillar 1: Copywriting (3/4)

**Strengths:**
- All CTAs are action-specific: "Generate RSA Keys", "Find & Select Sender", "Proceed to Decrypt", "Encrypt with AES Key", "Send Encrypted File". No generic "OK" / "Submit" / "Click Here" found in receiver or sender flows.
- Error messages are domain-precise: "Screen is not protected. Cannot process file on an unsecured window." (sender_screen.dart:183), "Failed to send key: …" (receiver_screen.dart:769), "Transfer cancelled — session wiped" (receiver_transfer_screen.dart:109).
- Empty/waiting states are explained: "A receiver must authorize you to begin." (sender_screen.dart:610), "Waiting for file transfer…" (receiver_screen.dart:573).
- Confirmation dialogs name the consequences: "This will delete your public key from Firebase and wipe your session data." (receiver_screen.dart:273).

**Issues:**
- `receiver_transfer_screen.dart` lines 69-71: Three `_StatusStep` labels embed emoji characters (`📡`, `🔐`, `✅`). In a security-hardened app targeting Android release builds, emoji rendering is OEM-dependent and the choice signals consumer-casual rather than professional-secure.
- `download_confirm_screen.dart` line 365: CTA `'✅ Done'` mixes emoji into an action button label. The existing `FilledButton.icon` + icon pattern used elsewhere (line 277-284 in receiver_transfer_screen.dart) is the correct approach.
- "Cancel" appears in `_generateKeys` dialog (receiver_screen.dart:150) — acceptable in a destructive-action confirmation context, not flagged.

### Pillar 2: Visuals (3/4)

**Strengths:**
- `ReceiverTransferScreen` leads with a bouncing 88px download icon (`_bounceCtrl` repeating animation), establishing immediate visual focus. The focal point is clear.
- `StepCard` uses `AnimatedContainer` with a glowing step-number badge (blurRadius 8, offset Offset(0,2)) and `AnimatedOpacity` at the parent for sequential disclosure — professional progressive-reveal pattern.
- `_WaitingForConnectionWidget` uses `ScaleTransition` + `FadeTransition` on a pulsing circle, which correctly communicates an async-wait state without a raw `CircularProgressIndicator`.
- `CrypButton` 3D depth system (4px shadow layer, `AnimatedPositioned` press-down) provides tactile feedback that standard Flutter buttons lack.
- `GlassContainer` with `BackdropFilter` (blur σ=12) creates consistent layering that matches the GitHub Dark surface hierarchy.

**Issues:**
- Body heading "Incoming File" (receiver_transfer_screen.dart line 219) duplicates the AppBar title. This is visible dead space — the user reads the same string twice in the first 200px of scroll. The body heading should display `widget.fileName` with ellipsis overflow, giving the user immediate file-identity confirmation.
- `_KeyManagerSheet` (receiver_screen.dart lines 869-913) has no empty state for `_sentKeys`. When the list is empty after loading, the "Shared Keys" section header appears alone with no children, which reads as a broken list rather than a confirmed-empty state. A brief "No keys shared yet" text would close this gap.
- Icon-only button: `IconButton(icon: Icon(Icons.sync_alt_rounded))` at receiver_screen.dart:512 has no `tooltip` property. It changes the selected sender, which is a session-altering action — tooltip is required for accessibility and discoverability.

### Pillar 3: Color (3/4)

**Theme token usage (correct):**
- `cs.primary`, `cs.secondary`, `cs.error`, `cs.onSurfaceVariant`, `cs.outlineVariant`, `cs.primaryContainer` used throughout `receiver_transfer_screen.dart` — well-tokenized.
- `AppTheme.primaryBlue`, `AppTheme.textSecondary`, `AppTheme.textMain` constants used correctly in `sender_screen.dart` and `receiver_screen.dart`.
- `AppTheme.glassBg` / `AppTheme.glassBorder` centralized in `GlassContainer` — single source of truth.

**Issues (raw color calls):**
- 31 occurrences of `Colors.*` across receiver files, 15 of which are in `receiver_screen.dart` alone. Notable examples:
  - `Colors.green.withValues(alpha: 0.1)` used as background tint in 4 separate `GlassContainer` calls (receiver_screen.dart lines 429, 467). This should be `cs.tertiary.withValues(alpha: 0.1)` or a named AppTheme constant.
  - `Colors.orange` in close-session dialog (receiver_screen.dart:265) is a one-off with no token equivalent. Map to `cs.error` for consistency.
  - `Colors.deepPurple` in `StatusBanner` (shared_widgets.dart:288) is the most egregious departure — it has no relation to the GitHub Dark palette or any AppTheme constant.
  - `Colors.indigo` / `Colors.indigoAccent` in `_ReceiverBadge` (sender_screen.dart:824-828) appear only in this one widget with no semantic justification.
- No hardcoded hex literals found in receiver/sender dart files — that constraint is clean.
- Accent (`primaryBlue` / `cs.primary`) applied only on interactive elements and active-state indicators — 60/30/10 intent is broadly maintained despite the raw color leakage.

### Pillar 4: Typography (3/4)

**Font system:**
- Two-font system: Inter (body, via `GoogleFonts.interTextTheme`) and Poppins (headings/labels, via `GoogleFonts.poppins()`). This is the declared design intent and is applied consistently.
- `AppBar` titles use `GoogleFonts.poppins(fontSize: 18, fontWeight: w600)` from the theme — consistent.
- `GlassButton` and `CrypButton` both override to `GoogleFonts.poppins(fontSize: 15, fontWeight: w600)` — consistent across all interactive elements.

**Font size distribution in receiver + transfer screens:**
- 11 (SecurityBadge only), 12, 13, 14, 15 (buttons), 20, 22 — 7 distinct sizes in use.
- 13 is the dominant body size across info rows, step tile labels, and list tiles. This is consistent and intentional.
- 22 (`fontSize: 22` at receiver_transfer_screen.dart:222) is used only once for the "Incoming File" heading — acceptable for a hero title.
- 20 appears in the close-session dialog heading (receiver_screen.dart:269) — matches decrypt_screen.dart pattern.

**Issues:**
- Font sizes are specified as raw doubles rather than referencing `Theme.of(context).textTheme` slots. This means `MediaQuery` text-scale accessibility settings do not apply. A user with system large-text enabled will see no change in the app's font sizes. The risk is highest for the 11px `SecurityBadge` label, which becomes unreadable at default size on small screens.
- `FontWeight.bold` used in `_Row` (receiver_screen.dart:944) vs `FontWeight.w600` used everywhere else for "semibold emphasis" — a minor inconsistency that should standardize on `w600`.

### Pillar 5: Spacing (4/4)

**Spacing is systematic and well-applied:**
- `receiver_transfer_screen.dart`: Outer `Padding` is `EdgeInsets.symmetric(horizontal: 24, vertical: 32)` — generous and intentional for a focus screen.
- `StepTile` margin: `EdgeInsets.only(bottom: 10)`, padding `EdgeInsets.symmetric(horizontal: 16, vertical: 12)` — compact and consistent.
- `SizedBox` gaps in receiver_transfer_screen.dart: 24 / 20 / 28 — follow an 8pt-based rhythm (24=3×8, 20 is 4pt off but acceptable given the fixed-height layout).
- `receiver_screen.dart` body: `EdgeInsets.symmetric(horizontal: 20, vertical: 10)` — slightly tighter than the transfer screen, appropriate for a scrollable multi-step flow.
- `StepCard` internal padding: `EdgeInsets.all(20)` — consistent across all step cards in both sender and receiver flows.
- No arbitrary pixel values (e.g., `EdgeInsets.only(top: 7.5)`) found. All spacing values are multiples of 4 or round numbers aligned to an 8pt grid.
- Inter-card gap of `SizedBox(height: 16)` is used uniformly throughout `receiver_screen.dart` build method (lines 606, 613, 620).

### Pillar 6: Experience Design (4/4)

**Loading states:**
- `receiver_screen.dart`: `_checkingStatus` drives `LinearProgressIndicator` in step 1 (line 422); `_loadingReadyState` drives `LinearProgressIndicator` in step 2 (line 464); `_handshaking` drives `LinearProgressIndicator` in step 3 (line 524).
- `_FindSenderSheet`: Per-user `_sendingKey[u.uid]` drives an inline `CircularProgressIndicator` (line 823-826) replacing the Send button — excellent granular loading.
- `_KeyManagerSheet`: `_loading` drives `CircularProgressIndicator.centered` before the list renders (line 898).
- `ReceiverTransferScreen`: `_bounceCtrl` + `_runSteps` animated sequence communicates async verification visually without blocking on a raw spinner.
- `SenderScreen`: `_encrypting` drives `_EncryptionProgressWidget` with a two-phase `LinearProgressIndicator` (read 0-70%, encrypt 70-100%) and percentage label — best-in-class progress feedback.

**Error states:**
- `_showError()` in both `ReceiverScreen` and `SenderScreen` surfaces errors as themed `SnackBar` with `colorScheme.error` background.
- `_sendKey` failure in `_FindSenderSheet` shows a `SnackBar` with `Colors.red` (minor — should use `cs.error`) but the state is reset correctly for retry.
- `_loadMetadata` in `ReceiverTransferScreen` catches and degrades gracefully (line 128-131) — the UI shows `'—'` placeholders rather than throwing.
- `isFlagSecureActive()` pre-flight check in `SenderScreen._encryptFile()` surfaces a specific actionable error and aborts cleanly.

**Kill-switch / session-terminated state:**
- `ReceiverTransferScreen._onSessionStateChanged()` pops all routes to root and shows "Transfer cancelled — session wiped" SnackBar (lines 104-113).
- `_cancelled` flag short-circuits `_runSteps` async chain to prevent `setState` after pop (line 139).
- `PopScope(canPop: _allStepsDone)` blocks back-navigation during the step sequence, preventing half-loaded state navigation.
- `CrypButton` session-state visual system: amber/lock (locked), primary/spinner (decrypting), error-red/block (terminated) — interactive affordance is clearly removed for non-open states.

**Empty/disabled states:**
- `GlassButton(onPressed: null)` applies `Opacity(0.5)` to communicate disabled state (shared_widgets.dart:80-82).
- Steps 2 and 3 use `AnimatedOpacity(opacity: done ? 1.0 : 0.4)` for sequential-disclosure disabled state — clear visual hierarchy.
- `_sessionLocked` prevents close-session while transfer is in progress with a SnackBar explanation (receiver_screen.dart:202-207).
- `PopScope(canPop: !_encrypting && !_encryptingKey)` in SenderScreen prevents navigation during active crypto operations.

**Minor gap:**
- `_KeyManagerSheet._sentKeys` empty list produces a blank "Shared Keys" section with no empty-state message. This is isolated to a settings sheet, not a primary flow — scored as informational only, not a pillar deduction.

---

## Registry Safety

No `components.json` found — shadcn not initialized. Registry audit skipped.

---

## Files Audited

- `lib/presentation/receiver/receiver_screen.dart` (948 lines)
- `lib/presentation/receiver/receiver_transfer_screen.dart` (406 lines)
- `lib/presentation/sender/sender_screen.dart` (847 lines)
- `lib/presentation/widgets/shared_widgets.dart` (550 lines)
- `lib/app_theme.dart` (111 lines)
- `.planning/phases/02-receivertransferscreen-hardening-memory-safety/02-01-SUMMARY.md` (context)
