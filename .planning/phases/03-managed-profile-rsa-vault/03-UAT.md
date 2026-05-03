---
status: testing
phase: 03-managed-profile-rsa-vault
source: 03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-03-SUMMARY.md, 03-04-SUMMARY.md, 03-05-SUMMARY.md
started: 2026-05-03T00:00:00Z
updated: 2026-05-03T00:03:00Z
---

## Current Test

number: 3
name: Key Vault Shows Active Key Fingerprint
expected: |
  With an existing RSA key pair, the Key Vault screen shows an "RSA-2048" algorithm label and a 16-character uppercase hex fingerprint. Two action buttons — Regenerate and Delete — are visible.
awaiting: investigating fix

## Tests

### 1. Key Vault Entry in Sidebar Drawer
expected: Open the app's sidebar drawer. A "Key Vault" menu entry is visible (the old "Generate RSA Keys" option is gone). Tapping it closes the drawer and navigates to the RSA Key Vault screen.
result: pass

### 2. RSA Key Vault Screen Opens
expected: After navigating to Key Vault (via drawer or banner), the screen opens. The biometric gate fires — on this build it auto-passes. The vault screen is now visible showing key status.
result: pass

### 3. Key Vault Shows Active Key Fingerprint
expected: With an existing RSA key pair, the Key Vault screen shows an "RSA-2048" algorithm label and a 16-character uppercase hex fingerprint (e.g., "A1B2C3D4E5F60123"). Two action buttons — Regenerate and Delete — are visible below the key info.
result: issue
reported: "both sender and receiver cannot Generate, Regenerate or Delete Keys"
severity: blocker

### 4. Regenerate Keys Flow
expected: Tap the Regenerate button in Key Vault. A confirmation dialog appears before any action is taken. After confirming, the key is regenerated — the fingerprint displayed on screen changes to reflect the new key pair. A success snackbar or indicator is shown.
result: issue
reported: "both sender and receiver cannot Generate, Regenerate or Delete Keys"
severity: blocker

### 5. Delete Keys Flow
expected: Tap the Delete button in Key Vault. A confirmation dialog appears. After confirming, the key is deleted — the screen transitions from the "active key" view to a "no key" state (showing an option to generate a new key pair).
result: issue
reported: "both sender and receiver cannot Generate, Regenerate or Delete Keys"
severity: blocker

### 6. No-Keys Warning Banner in ReceiverScreen
expected: On an account with no RSA keys (e.g., after deleting via vault), navigate to the Receiver screen. Step 1 shows an amber warning banner ("No RSA keys found — tap to generate" or similar). Tapping the banner navigates to the Key Vault screen. After returning, the banner is gone if a key was generated.
result: [pending]

## Summary

total: 6
passed: 2
issues: 3
pending: 1
skipped: 0
blocked: 0

## Gaps

- truth: "Generate, Regenerate, and Delete key operations complete successfully in Key Vault"
  status: failed
  reason: "User reported: both sender and receiver cannot Generate, Regenerate or Delete Keys"
  severity: blocker
  test: 3
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
