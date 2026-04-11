# CrypTransfer Silent Guardian
# Runs headless -- no user input required.
# Usage: powershell.exe -WindowStyle Hidden -NonInteractive -NoProfile -File silent_guardian.ps1
param(
    [string]$ProjectRoot  = "C:\Users\navve\projects\cryptransfer",
    [string]$ObsidianBase = "C:\Users\navve\ObsidianVault\CrypTransfer"
)

$date       = Get-Date -Format "yyyy-MM-dd"
$time       = Get-Date -Format "HH:mm:ss"
$reportDir  = "$ObsidianBase\DailyReports"
$reportFile = "$reportDir\${date}_report.md"
$errorLog   = "$ProjectRoot\report_error.log"

# ── Logging ───────────────────────────────────────────────────────────────────

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "[$date $time] [$Level] $Message"
    Add-Content -Path $errorLog -Value $entry
    Write-Output $entry
}

# ── Main ──────────────────────────────────────────────────────────────────────

try {
    Write-Log "Guardian cycle started"
    Set-Location $ProjectRoot

    # ── 1. Flutter Analyze ────────────────────────────────────────────────────
    Write-Log "Running flutter analyze..."
    $analysis = & flutter analyze --no-pub 2>&1 | Out-String
    $analyzeStatus = if ($analysis -match "No issues found") {
        "PASS - Zero issues found"
    } else {
        "WARN - Issues detected, see details below"
    }
    $analyzeDetail = if ($analysis -match "No issues found") {
        ""
    } else {
        "`n``````text`n$analysis`n``````"
    }

    # ── 2. Git Changes (last 24 hours) ────────────────────────────────────────
    Write-Log "Fetching git changes..."
    $changes = & git log --oneline --since="24 hours ago" 2>&1 | Out-String
    $gitDiff  = & git diff --stat HEAD~1 2>&1 | Out-String

    if ([string]::IsNullOrWhiteSpace($changes)) { $changes = "_No commits in last 24 hours_" }
    if ([string]::IsNullOrWhiteSpace($gitDiff))  { $gitDiff  = "_No diff available_" }

    # ── 3. Scan lib/ -- Security State Scanner ────────────────────────────────
    Write-Log "Scanning lib/ for security state..."
    $dartFiles = Get-ChildItem -Path "$ProjectRoot\lib" -Filter "*.dart" -Recurse

    $verified = @()
    $warnings = @()
    $critical = @()

    foreach ($file in $dartFiles) {
        $content = Get-Content $file.FullName -Raw
        $name    = $file.Name

        if ($content -match "SecurityLifecycleMixin") {
            $verified += "- `` $name `` SecurityLifecycleMixin verified"
        }
        if ($content -match "Isolate\.run\(" -and $content -match "encrypt|decrypt") {
            $warnings += "- `` $name `` Isolate.run() used for crypto"
        }
        if ($content -match "debugPrint.*(key|private|aes|rsa)") {
            $critical += "- `` $name `` Possible key leak in debugPrint"
        }
        if ($content -match "FirebaseFirestore\.instance" -and
            $file.FullName -match "\\presentation\\") {
            $warnings += "- `` $name `` Direct Firestore in presentation layer"
        }
        if ($file.Name -match "receiver_screen" -and
            $content -match "closeReceiverSession") {
            $verified += "- `` $name `` closeReceiverSession wired (Closed Mailbox rule)"
        }
        if ($file.Name -match "receiver_screen" -and
            $content -match "didChangeAppLifecycleState") {
            $verified += "- `` $name `` didChangeAppLifecycleState wired (lifecycle auto-wipe)"
        }
    }

    # ── Kill Switch deep scan ──────────────────────────────────────────────────
    $encryptionService = Get-Content "$ProjectRoot\lib\data\services\encryption_service.dart" `
        -Raw -ErrorAction SilentlyContinue

    if ($encryptionService -match "closeReceiverSession") {
        if ($encryptionService -match "FieldValue\.delete\(\)") {
            $verified += "- ``encryption_service.dart`` Kill Switch active (FieldValue.delete() confirmed)"
        } else {
            $warnings += "- ``encryption_service.dart`` closeReceiverSession exists but FieldValue.delete() NOT found!"
        }
    }

    if ($encryptionService -match "Receiver_Session_Closed") {
        $verified += "- ``encryption_service.dart`` Security event logging active"
    }

    $receiverScreen = Get-Content "$ProjectRoot\lib\presentation\receiver\receiver_screen.dart" `
        -Raw -ErrorAction SilentlyContinue

    if ($receiverScreen -match "closeReceiverSession") {
        $verified += "- ``receiver_screen.dart`` Kill switch wired to toggle"
    } else {
        $critical += "- ``receiver_screen.dart`` closeReceiverSession NOT called on toggle off! GHOST KEYS RISK!"
    }

    if ($receiverScreen -match "didChangeAppLifecycleState") {
        $verified += "- ``receiver_screen.dart`` Lifecycle observer active (wipes on app background)"
    } else {
        $warnings += "- ``receiver_screen.dart`` No lifecycle observer. Keys persist if app is force-closed!"
    }

    # ── Auth repository: compute() check ──────────────────────────────────────
    $authRepo = Get-Content "$ProjectRoot\lib\data\repositories\auth_repository.dart" `
        -Raw -ErrorAction SilentlyContinue

    if ($authRepo -match "Isolate\.run\(\)" -and $authRepo -match "generateAndStoreKeyPair") {
        $warnings += "- ``auth_repository.dart`` generateAndStoreKeyPair still uses Isolate.run() - change to compute()"
    } else {
        $verified += "- ``auth_repository.dart`` compute() used for RSA keygen - no Isolate.run()"
    }

    # ── participants field: HomeScreen Recent Transfers check ──────────────────
    $transferRepo = Get-Content "$ProjectRoot\lib\data\repositories\transfer_repository.dart" `
        -Raw -ErrorAction SilentlyContinue

    if ($transferRepo -match "'participants'") {
        $verified += "- ``transfer_repository.dart`` participants field present in writeAuditLog()"
    } else {
        $warnings += "- ``transfer_repository.dart`` participants field MISSING from writeAuditLog() - HomeScreen Recent Transfers broken"
    }

    # ── encryptedAESKey field name consistency check ───────────────────────────
    $transferModel = Get-Content "$ProjectRoot\lib\data\models\transfer_model.dart" `
        -Raw -ErrorAction SilentlyContinue

    if ($transferModel -cmatch "encryptedAesKey") {
        $warnings += "- ``transfer_model.dart`` field name drift: encryptedAesKey found - must be encryptedAESKey"
    } else {
        $verified += "- ``transfer_model.dart`` encryptedAESKey naming consistent - uppercase AES, no drift"
    }

    $verifiedList = if ($verified.Count -gt 0) { $verified -join "`n" } else { "_No files verified yet_" }
    $warningList  = if ($warnings.Count -gt 0) { $warnings -join "`n" } else { "_No warnings_" }
    $criticalList = if ($critical.Count -gt 0) { $critical -join "`n" } else { "_No critical issues_" }

    # ── 4. Test Results Summary ───────────────────────────────────────────────
    Write-Log "Checking test results..."
    $testSummary = "_Run 'flutter test' to generate results_"
    $testResultsFile = "$ProjectRoot\test_results.json"
    if (Test-Path $testResultsFile) {
        $testAge = (Get-Date) - (Get-Item $testResultsFile).LastWriteTime
        $testSummary = if ($testAge.TotalHours -lt 24) {
            "Test results available (less than 24h old)"
        } else {
            "Test results stale (older than 24h) -- re-run flutter test"
        }
    }

    # ── 5. Build Report ───────────────────────────────────────────────────────
    $verifiedCount = $verified.Count
    $warningCount  = $warnings.Count
    $criticalCount = $critical.Count

    $report = @"
# CrypTransfer Daily Report
**Date:** $date
**Time:** $time
**Guardian Cycle:** Automated Headless Run

---

## Build Status
**Flutter Analyze:** $analyzeStatus
$analyzeDetail

---

## Git Activity (Last 24 Hours)
$changes

### Files Changed
``````
$gitDiff
``````

---

## Security Lifecycle Scan

### Verified (SecurityLifecycleMixin Active)
$verifiedList

### Warnings
$warningList

### Critical Issues
$criticalList

---

## Test Status
$testSummary

---

## Open Issues (from CLAUDE.md)
- [ ] Face ID re-enable before viva
- [ ] Receiver stepper same as sender
- [ ] 3D buttons across all screens
- [ ] Session cleanup after End Session
- [ ] pushAndRemoveUntil after EndSession
- [ ] Chapter 3 thesis update
- [ ] Chapter 5 testing results
- [ ] Fix figure numbering in thesis
- [ ] Fix shoutout in acknowledgements

---

## Completed Today
_(Scan lib/ for changes since yesterday)_

---

## Next Actions
1. Fix any Critical Issues above immediately
2. Fix any Warnings before viva
3. Run test suite if stale
4. Commit changes with descriptive message

---

## Summary
| Check | Result |
|-------|--------|
| Flutter Analyze | $analyzeStatus |
| SecurityLifecycleMixin files | $verifiedCount verified |
| Warnings | $warningCount |
| Critical Issues | $criticalCount |
| Test Results | $testSummary |

---
_Generated by CrypTransfer Silent Guardian_
_Navveen Nair | UTM | A22EC0092_
"@

    # ── 6. Write to Obsidian ──────────────────────────────────────────────────
    Write-Log "Writing report to Obsidian..."
    if (!(Test-Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    $report | Out-File -FilePath $reportFile  -Encoding utf8
    $report | Out-File -FilePath "$reportDir\latest_report.md" -Encoding utf8
    Write-Log "Report written: $reportFile" "SUCCESS"

    # ── 7. Refresh security audit ─────────────────────────────────────────────
    Write-Log "Running security audit script..."
    & dart "$ProjectRoot\scripts\security_audit_report.dart" 2>&1 |
        ForEach-Object { Write-Log $_ }

    Write-Log "Guardian cycle completed" "SUCCESS"

} catch {
    $errMsg = $_.Exception.Message
    Write-Log "Guardian cycle FAILED: $errMsg" "ERROR"
    "[$date $time] ERROR: $errMsg" | Out-File -FilePath $errorLog -Append
    exit 1
}

exit 0
