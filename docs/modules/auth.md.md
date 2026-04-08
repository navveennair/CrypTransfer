---
tags: [module, auth, agent-active]
status: complete
---

# Module: Authentication

## Responsibility
Handles user registration, login, logout, and biometric authentication via Firebase Auth.

## Files Owned
- lib/src/features/auth/

## Dependencies
- Firebase Auth
- flutter_secure_storage
- local_auth (biometric)

## Current Status
✅ Firebase Auth login/register done
✅ Biometric auth implemented (bypassed for testing)
✅ Role selection (Sender/Receiver) done

## Agent Instructions
1. Never store raw passwords
2. Biometric bypass is TEMPORARY — re-enable before viva
3. Update this doc after any auth flow changes

## Open Tasks
- [ ] Re-enable biometric authentication before viva