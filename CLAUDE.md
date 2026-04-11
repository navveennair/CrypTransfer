
---

## Automation Protocol & Scripts

### Background Execution Policy (Non-Interactive)
To ensure scripts run via Obsidian/Task Scheduler without GUI popups:
- **CLI Wrapper:** `powershell.exe -WindowStyle Hidden -NonInteractive -NoProfile -Command`
- **I/O Rule:** No `stdin` or `Read-Host`. All output must redirect to files or `stdout`.
- **Error Handling:** Redirect stderr to `report_error.log`.

### Command: [Sync & Daily Report]
**Trigger:** "daily report" OR "update status"
**Logic:**
1. **Analyze:** Run `flutter analyze --no-pub`.
2. **Sync State:** - Scan `lib/` for new features (e.g., `DownloadConfirmScreen`).
   - Move matching items from `Known Open Issues` to `Completed Features`.
   - Add any `flutter analyze` errors to `Known Open Issues`.
3. **Log Audit:** Check `git diff --stat` for the last 24 hours.
4. **Update Docs:**
   - Overwrite `CLAUDE.md` with the new status.
   - Generate `DailyReports/{date}_report.md` in Obsidian vault.
5. **Report Content:** - [Changes Made] (via git)
   - [Resolved Issues] (moved to completed)
   - [Current Blockers] (flutter errors + remaining issues)
   - [Next Action] (per Week Plan)

### Script: PowerShell Headless Wrapper
```powershell
# Use this block to execute logic silently
$reportPath = "C:\Users\navve\ObsidianVault\CrypTransfer\DailyReports\$(Get-Date -Format 'yyyy-MM-dd')_report.md"
try {
    # 1. Sync Logic here
    # 2. Analyze here
    # 3. Write to $reportPath
} catch {
    $_.Exception.Message | Out-File -FilePath "C:\Users\navve\projects\cryptransfer\report_error.log" -Append
}
```

---

## 🤖 Automation & Reporting Protocol
- **Guardian Cycle:** 12:00 PM to 12:00 PM (Next Day)
- **Background Policy:** Execute using:
  `powershell.exe -WindowStyle Hidden -NonInteractive`
- **Primary Report Path:**
  `C:\Users\navve\ObsidianVault\CrypTransfer\DailyReports\`
- **Security Audit Path:**
  `C:\Users\navve\ObsidianVault\CrypTransfer\Security\`
- **Error Log:**
  `C:\Users\navve\projects\cryptransfer\report_error.log`

### 🔄 Sync Commands
| Trigger | Action |
|---------|--------|
| daily report | flutter analyze + git diff + Obsidian MD |
| update status | Scan lib/ move Open→Completed in CLAUDE.md |
| security audit | Run SecurityLifecycleMixin scan + report |
| run tests | flutter test + write Obsidian test report |

### 🔍 State Scanner Rules
When scanning lib/ for status updates:
- File contains SecurityLifecycleMixin → mark VERIFIED
- File contains compute() for crypto → mark SECURE
- File contains Isolate.run() for crypto → flag WARNING
- File contains raw FirebaseFirestore in screen → flag ISSUE
- File contains debugPrint with key data → flag CRITICAL
- receiver_screen.dart contains closeReceiverSession → mark VERIFIED (Closed Mailbox rule)
- receiver_screen.dart contains didChangeAppLifecycleState → mark VERIFIED (lifecycle auto-wipe)

---

## ✅ Completed Features

- [x] SecurityLifecycleMixin created
- [x] SenderScreen pre-flight wipe (`_wipeSensitiveData()` + handoff destruction)
- [x] DecryptScreen Save & Suicide pattern (`_saveAndWipe()`, `_Phase.done`, clean-room decrypt)
- [x] SecurityLifecycleMixin applied to SenderScreen, DecryptScreen, TransferProgressScreen, DownloadConfirmScreen, EndSessionScreen
- [x] Non-repudiation Firestore listener in TransferProgressScreen
- [x] `receiverStatus` field updated at each decrypt phase in DecryptScreen
- [x] `updateReceiverStatus()` in TransferRepository
- [x] closeReceiverSession Kill Switch (`EncryptionService.closeReceiverSession()` — public key deleted from Firestore, private key wiped from device, batch-delete rsa_key_transfers + notifications)
- [x] Auto-Wipe on toggle/app close/screen exit:
  - `ReceiverScreen._onToggleReady()` — full open/close mailbox flow
  - `ReceiverScreen._showCloseSessionDialog()` — confirmation bottom sheet before close
  - `WidgetsBindingObserver` + `didChangeAppLifecycleState` — auto-wipe on app pause/detach
  - `PopScope` wrapping ReceiverScreen Scaffold — wipe on back navigation
  - `_sessionLocked` state + `_showSessionLockedBanner()` — blocks close during active transfer
- [x] Session hijack prevention tested
- [x] TC-WIPE-001 to TC-WIPE-006 all passing (`test/security/session_wipe_test.dart`)
- [x] Silent Guardian Kill Switch scanner (FieldValue.delete check, ReceiverScreen wiring check, lifecycle observer check)
- [x] Obsidian Security audit report (`scripts/security_audit_report.dart`)

## 🔲 Known Open Issues

- [ ] Face ID re-enable before viva
- [ ] Receiver stepper same as sender
- [ ] 3D buttons across all screens
- [ ] Session cleanup after End Session
- [ ] pushAndRemoveUntil after EndSession
- [ ] Chapter 3 thesis update
- [ ] Chapter 5 testing results
- [ ] Fix figure numbering in thesis
- [ ] Fix shoutout in acknowledgements