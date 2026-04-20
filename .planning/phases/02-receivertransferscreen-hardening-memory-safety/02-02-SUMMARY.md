---
phase: 02-receivertransferscreen-hardening-memory-safety
plan: 02
subsystem: security, memory
tags: [file-picker, plaintext-remanence, android]

# Dependency graph
requires:
  - phase: 02-receivertransferscreen-hardening-memory-safety
    provides: Hardened ReceiverTransferScreen
provides:
  - SenderScreen with memory-efficient file picker (withData: kIsWeb)
  - Cloud-URI guard in SenderScreen to prevent null-path silent failures
  - Platform-aware _encryptFile guard for web vs mobile/desktop
affects: [sender-flow, security-verification]

# Tech tracking
tech-stack:
  added: []
  patterns: [Path-based chunked file reading, platform-aware guards]

key-files:
  created: []
  modified: 
    - lib/presentation/sender/sender_screen.dart

key-decisions:
  - "Changed withData from true to kIsWeb to eliminate unregistered plaintext copies on Android."
  - "Added explicit null-path check to catch cloud-URI edge cases before encryption."
  - "Updated downstream guards to ensure path-based reads flow correctly on non-web."

patterns-established:
  - "Pattern: withData: kIsWeb for memory-safe file picking on mobile/desktop."
  - "Pattern: Platform-aware file existence checks (kIsWeb && bytes == null vs !kIsWeb && path == null)."

requirements-completed: [MEM-01]

# Metrics
duration: 10min
completed: 2026-04-18
---

# Phase 02: SenderScreen Memory Safety Summary (Plan 02)

**Eliminated unregistered plaintext copies on Android by switching to path-based file reads and implemented cloud-URI guards.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-04-18T10:15:00Z
- **Completed:** 2026-04-18T10:25:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Reduced the memory footprint of `SenderScreen` on Android by ensuring `PlatformFile.bytes` remains null.
- Implemented a user-facing SnackBar for cloud-URI picks (Google Drive/Gmail) that lack a local file path.
- Updated `_encryptFile` to correctly handle both path-based (mobile/desktop) and bytes-based (web) encryption flows.

## Task Commits

1. **Task 1: withData: kIsWeb + null-path cloud-URI guard in _pickFile** - `n/a` (manual edit)

## Files Created/Modified
- `lib/presentation/sender/sender_screen.dart` - Updated _pickFile and _encryptFile with memory-safe guards.

## Decisions Made
- None - followed plan as specified (with correction to kIsWeb vs !kIsWeb logic).

## Deviations from Plan

### Auto-fixed Issues

**1. [Correctness] withData: kIsWeb correction**
- **Found during:** Task 1 (FilePicker update)
- **Issue:** One plan description mentioned `withData: !kIsWeb`, which would have enabled bytes on Android and disabled them on Web — the opposite of the security intent.
- **Fix:** Used `withData: kIsWeb` to ensure bytes are ONLY loaded on web where they are mandatory.
- **Files modified:** lib/presentation/sender/sender_screen.dart
- **Verification:** Logical verification; kIsWeb is true on Web, false elsewhere.

---

**Total deviations:** 1 auto-fixed (correctness)
**Impact on plan:** Essential for correctly implementing the memory safety goal on both platforms.

## Issues Encountered
None.

## Next Phase Readiness
- SenderScreen is now memory-hardened.
- Phase 2 is complete.
- Ready for full system verification.

---
*Phase: 02-receivertransferscreen-hardening-memory-safety*
*Completed: 2026-04-18*
