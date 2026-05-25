---
status: complete
phase: 07-sender-reactive-cleanup-sync
source: [commit a03465c — global glassmorphic 3D design system + handshake fixes]
started: 2026-05-25T00:00:00Z
updated: 2026-05-25T00:00:00Z
note: "Cross-cutting commit — no dedicated phase. Filed under Phase 07 as it was committed at milestone v1.0 completion."
---

## Current Test

[testing complete]

## Tests

### 1. CrypButton / GlassButton press animation
expected: Tap and hold any CrypButton or GlassButton. Button scales down on press, springs back on release. Subtle haptic tap fires on press.
result: pass

### 2. Auth screens glassmorphic styling
expected: Splash, Login, and Register screens all show the GlassContainer logo/hero card with frosted-glass blur effect, primary-colour CrypButton CTAs, and GlassButton for Google sign-in. No flat/opaque cards visible.
result: issue
reported: "Fonts are supposed to be black in buttons that are dark in colour, white in dark surroundings. font isnt clear."
severity: major

### 3. Sidebar InkWell ripples on transparent surface
expected: Open the sidebar drawer and tap any menu item. An InkWell ripple should be visible on the glassmorphic surface (not clipped or invisible due to transparency).
result: pass
note: "Ripples work but font colors are dark on dark glassmorphic background — added as issue 3b"

### 3b. Sidebar drawer font colors
expected: All sidebar menu item labels and section headers are light (white/near-white) so they're readable against the dark glassmorphic background.
result: issue
reported: "fonts are dark in colour with the background in sidebar drawer"
severity: major

### 4. Find Friends — disconnect removes from both users
expected: From Find Friends, tap the PopupMenu on a Connected user and select Disconnect. After confirming, that user's status immediately reverts to "not connected" on your side. On the other device (the partner), their connection to you is also removed — they no longer see you as Connected either (no orphan one-directional doc).
result: pass

### 5. Find Friends — no spurious Connect on already-connected user
expected: Search for a user you are already connected with. The result row should show "Connected" badge (or Send action if handshake in progress), NOT a "Connect" button. The _streamReady guard prevents flashing "Connect" before the stream resolves.
result: pass
note: "No flicker. Partner's Connected status also persists correctly once proposer connects — bidirectional display confirmed."

### 6. Mutual accept TOCTOU safety (runTransaction)
expected: Accepting an incoming connection proposal completes successfully without duplicate handshake docs appearing (e.g. both parties tapping Accept simultaneously should not create two docs or leave an orphaned state). This is structural — skip if you can't simulate simultaneous accepts.
result: pass
note: "Exactly one doc exists in neutral_handshakes with fields: createdAt, partnerId, partnerUsername, proposerId, proposerUsername, status, updatedAt. No duplicates."

## Summary

total: 7
passed: 5
issues: 2
pending: 0
skipped: 0
blocked: 0
inline_fixes: 2

## Gaps

- truth: "Button label text is black on dark/coloured buttons and white on dark backgrounds — readable in all cases"
  status: failed
  reason: "User reported: Fonts are supposed to be black in buttons that are dark in colour, white in dark surroundings. font isnt clear."
  severity: major
  test: 2
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
