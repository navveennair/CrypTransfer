---
type: community
cohesion: 0.10
members: 22
---

# Transfer & Repository Layer

**Cohesion:** 0.10 - loosely connected
**Members:** 22 nodes

## Members
- [[File Transfer Module]] - document - docs/modules/file-transfer.md
- [[HomeScreen]] - document - docs/modules/ui.md
- [[Navigation Model (pushAndRemoveUntil, pushReplacement)]] - document - docs/modules/ui.md
- [[Notification Document Schema (notifications{docId})]] - document - docs/modules/notifications.md
- [[NotificationModel + NotificationType enum]] - document - docs/modules/notifications.md
- [[NotificationService]] - document - docs/modules/notifications.md
- [[Notifications Module]] - document - docs/modules/notifications.md
- [[NotificationsScreen]] - document - docs/modules/notifications.md
- [[Overlay Notification Banner (_NotifBanner)]] - document - docs/modules/ui.md
- [[Shared Widgets (StepCard, UserAvatar, StatusBanner, SecurityBadge)]] - document - docs/modules/ui.md
- [[SidebarDrawer]] - document - docs/modules/ui.md
- [[Stepper Pattern (StepCard sequential flow)]] - document - docs/modules/ui.md
- [[Transfer Document Schema (transfers{transferId})]] - document - docs/modules/file-transfer.md
- [[TransferModel + TransferStatus enum]] - document - docs/modules/file-transfer.md
- [[TransferRepository]] - document - CLAUDE.md
- [[UIUX Module]] - document - docs/modules/ui.md
- [[cloud_firestore dependency (notifications)]] - document - docs/modules/notifications.md
- [[cloud_firestore dependency (transfer)]] - document - docs/modules/file-transfer.md
- [[firebase_storage dependency]] - document - docs/modules/file-transfer.md
- [[libdatarepositoriestransfer_repository.dart]] - code - docs/modules/file-transfer.md
- [[participants field in writeAuditLog()]] - document - CLAUDE.md
- [[path_provider dependency]] - document - docs/modules/file-transfer.md

## Live Query (requires Dataview plugin)

```dataview
TABLE source_file, type FROM #community/Transfer_&_Repository_Layer
SORT file.name ASC
```

## Connections to other communities
- 1 edge to [[_COMMUNITY_Firebase & Auth Stack]]
- 1 edge to [[_COMMUNITY_Encryption Service Core]]
- 1 edge to [[_COMMUNITY_Receiver Session & Crypto]]
- 1 edge to [[_COMMUNITY_Security Testing & Audit]]

## Top bridge nodes
- [[File Transfer Module]] - degree 10, connects to 3 communities
- [[UIUX Module]] - degree 7, connects to 1 community