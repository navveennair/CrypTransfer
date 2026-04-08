---
tags: [module, notifications, agent-active]
status: complete
---

# Module: Notifications

## Responsibility
Firestore-based receiver notifications when a file transfer is initiated.

## Files Owned
- lib/src/features/notifications/

## Dependencies
- Firebase Firestore

## Current Status
✅ Firestore notification on transfer initiation done

## Agent Instructions
1. Notifications must trigger on sender action, not on file upload completion
2. Update this doc after any notification changes

## Open Tasks
- [ ] Test notification delivery on cold start