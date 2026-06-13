---
quick_id: 260613-a1k
status: complete
date: 2026-06-13
---

## Summary

Added a 100 MB file size guard to `_pickFile()` in `sender_screen.dart`.

**Change:** 15 lines added across 2 edits:
1. Import `firebase_constants.dart`
2. Size check immediately after `result.files.first` — rejects oversized files with a red SnackBar
   before encryption or upload can begin

**Error message shown:** `"File too large — maximum is 100 MB (X.X MB selected)"`

`flutter analyze` passes with no issues.
