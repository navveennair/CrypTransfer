
---

# Command: Daily Report Generation

## Execution Context
- **Trigger:** "daily report"
- **Mode:** Background (Non-Interactive)
- **Logon Type:** S-1-5-18 (System) or Service Account to prevent GUI popups.


# Command: Update Status

## Logic
1. **Sync:** Move items from `Known Open Issues` to `Completed Features` based on recent file changes (e.g., if `DownloadConfirmScreen` exists, it is complete).
2. **Verification:** Run `flutter analyze`. If errors exist, add them back to `Open Issues`.
3. **Obsidian Write:** Overwrite `CLAUDE.md` with the refreshed state.
4. **No-GUI Policy:** Ensure this update process never triggers a window focus or interactive prompt.

## Background Execution Fix (CRITICAL)
If running via Windows Task Scheduler or Obsidian Shell:
- Use `-WindowStyle Hidden -NonInteractive` flags.
- Do NOT call `stdout` or `stdin` if the session is non-interactive.
- Redirect all errors to `report_error.log`.