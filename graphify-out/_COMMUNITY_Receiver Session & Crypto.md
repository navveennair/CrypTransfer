---
type: community
cohesion: 0.13
members: 15
---

# Receiver Session & Crypto

**Cohesion:** 0.13 - loosely connected
**Members:** 15 nodes

## Members
- [[Closed Mailbox Kill Switch Defence]] - document - docs/modules/security.md
- [[Closed Mailbox Rule (Kill Switch)]] - document - docs/modules/encryption.md
- [[Closed Mailbox UI (ReceiverScreen toggle flow)]] - document - docs/modules/ui.md
- [[EncryptionService]] - document - CLAUDE.md
- [[Ghost Mailbox Attack Threat]] - document - docs/modules/security.md
- [[KeyRepository]] - document - docs/modules/file-transfer.md
- [[Legacy Isolate.run() Path in AuthRepository]] - document - docs/modules/encryption.md
- [[RSA Key Manager Modal (_KeyManagerSheet)]] - document - docs/modules/ui.md
- [[RSA Key Transfer Document Schema (rsa_key_transfers{docId})]] - document - docs/modules/file-transfer.md
- [[ReceiverScreen]] - document - CLAUDE.md
- [[Startup Session Wipe KeyRepository.wipeAllSessionKeys()]] - document - docs/modules/security.md
- [[closeReceiverSession Kill Switch]] - document - CLAUDE.md
- [[closeReceiverSession(uid)]] - document - docs/modules/encryption.md
- [[local_auth dependency (biometric)]] - document - docs/modules/auth.md
- [[setupReceiverSession(uid)]] - document - docs/modules/encryption.md

## Live Query (requires Dataview plugin)

```dataview
TABLE source_file, type FROM #community/Receiver_Session_&_Crypto
SORT file.name ASC
```

## Connections to other communities
- 2 edges to [[_COMMUNITY_Firebase & Auth Stack]]
- 1 edge to [[_COMMUNITY_Transfer & Repository Layer]]

## Top bridge nodes
- [[KeyRepository]] - degree 3, connects to 1 community
- [[local_auth dependency (biometric)]] - degree 2, connects to 1 community
- [[Legacy Isolate.run() Path in AuthRepository]] - degree 2, connects to 1 community