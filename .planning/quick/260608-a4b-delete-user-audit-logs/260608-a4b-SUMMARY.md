---
quick_id: 260608-a4b
status: complete
date: 2026-06-08
---

# Quick Task 260608-a4b: Delete User Audit Logs — Summary

## What was done

Created `scripts/reset_user_audit.js` — a Node.js script (firebase-admin) that deletes all audit log documents for a given user UID, enabling a clean slate for development/testing.

## Collections cleaned by the script

| Collection | Method |
|---|---|
| `users/{uid}/audit_logs` | Delete all docs in subcollection |
| `users/{uid}/rsa_key_manager` | Delete all docs in subcollection |
| `transfer_logs` | Query `participants array-contains uid`, delete matches |

## Usage

```bash
# One-time setup
npm install firebase-admin   # from scripts/ or project root
# Add scripts/serviceAccountKey.json from Firebase Console → Service Accounts

# Run
node scripts/reset_user_audit.js <USER_UID>
```

## Files changed

- `scripts/reset_user_audit.js` — new utility script
