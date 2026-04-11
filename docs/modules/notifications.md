---
tags: [module, notifications, agent-active]
status: complete
---

# Module: Notifications

## Responsibility
Firestore-based notification system: in-app banners when a transfer is initiated,
unread badge on HomeScreen, full notification list screen, and mark-as-read mutations.

## Files Owned
- `lib/core/utils/notification_service.dart` — read-only streams + mark-read mutations
- `lib/data/models/notification_model.dart` — `NotificationModel` + `NotificationType` enum
- `lib/presentation/home/notifications_screen.dart` — notification list UI
- `lib/data/repositories/transfer_repository.dart` — `notifyReceiver()` writes the notification

## Dependencies
- `cloud_firestore` — notifications collection

## Notification Document Schema
```
notifications/{docId}
  toUserId:    String   — recipient UID
  fromUsername: String  — sender display name
  message:     String   — human-readable message
  type:        String   — 'file_received' | 'rsa_key_received'
  transferId:  String?  — linked transfer doc ID
  read:        bool     — false until opened
  createdAt:   Timestamp
```

## NotificationService API
| Method | Type | Purpose |
|--------|------|---------|
| `unreadCountStream(uid)` | `Stream<int>` | Badge count for HomeScreen |
| `allStream(uid)` | `Stream<List<...>>` | All notifications, newest first |
| `latestUnreadStream(uid)` | `Stream<Map?>` | Latest unread for banner display |
| `markRead(docId)` | `Future<void>` | Mark single notification read |
| `markAllRead(uid)` | `Future<void>` | Batch mark all read |

## Notification Trigger Points
| Trigger | Location | Type |
|---------|----------|------|
| Receiver sends RSA public key to sender | `KeyRepository.sendPublicKey()` | `rsa_key_received` |
| Sender initiates transfer | `TransferRepository.notifyReceiver()` | `file_received` |
| ReceiverScreen detects pending transfer | In-app `MaterialBanner` (not Firestore notif) | (in-app only) |

> **Note**: `rsa_key_received` notifications are written directly in `KeyRepository.sendPublicKey()`,
> not through `TransferRepository`. The notification document does **not** include a `fromUserId` field —
> only `fromUsername`. Firestore queries on `fromUserId` will return empty for this notification type.

## Current Status
✅ Firestore notification written on transfer initiation  
✅ `NotificationService` read streams done  
✅ `NotificationsScreen` with full list and mark-as-read  
✅ Unread badge count stream on HomeScreen  
✅ `latestUnreadStream` for banner display  
✅ ReceiverScreen Firestore `watchPendingTransfers` listener done  

## Agent Instructions
1. Notifications must trigger on sender action — before file upload completes
2. `notifyReceiver()` failures are non-critical — must not break the transfer flow
3. `fromUserId` is NOT stored in notification docs (only `fromUsername`) — Firestore queries on `fromUserId` will return empty
4. Update this doc after any notification changes

## Open Tasks
- [ ] Test notification delivery on cold start (app not running when transfer initiated)
