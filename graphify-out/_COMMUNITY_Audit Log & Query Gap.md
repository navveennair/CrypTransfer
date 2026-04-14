---
type: community
cohesion: 0.67
members: 3
---

# Audit Log & Query Gap

**Cohesion:** 0.67 - moderately connected
**Members:** 3 nodes

## Members
- [[Audit Log Document Schema (transfers_log{docId})]] - document - docs/modules/file-transfer.md
- [[HomeScreen Recent Transfers Firestore Query]] - document - docs/modules/ui.md
- [[participants Field Implementation Gap]] - document - docs/modules/file-transfer.md

## Live Query (requires Dataview plugin)

```dataview
TABLE source_file, type FROM #community/Audit_Log_&_Query_Gap
SORT file.name ASC
```
