---
phase: 06-synchronized-readiness-gate
test: WR-01
status: diagnosed
---

# Root Cause: Firestore rules block receiver from deleting handshake doc

`endSessionCleanup` (called by receiver on end session) attempts to batch-delete the
`handshakes/{handshakeId}` document. The Firestore rule at `firestore.rules:187` only
allows the **sender** to delete:

```
allow delete: if isAuthenticated() &&
               (resource.data.senderId == request.auth.uid || isAdmin());
```

The receiver is not the sender, so the delete fails with PERMISSION_DENIED.

## Fix

Extend the delete rule to also allow the receiver:

```
allow delete: if isAuthenticated() &&
               (resource.data.senderId == request.auth.uid ||
                resource.data.receiverId == request.auth.uid ||
                isAdmin());
```

## Files

- `firestore.rules:186-189` — handshakes delete rule
- `lib/data/repositories/key_repository.dart:704-706` — endSessionCleanup batch.delete
- `lib/presentation/receiver/receiver_end_session_screen.dart:187-191` — caller
