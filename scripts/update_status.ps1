# Scans lib/ and reports completion status against defined checks.
# Usage: powershell -ExecutionPolicy Bypass -File scripts\update_status.ps1
param(
    [string]$ProjectRoot = "C:\Users\navve\projects\cryptransfer"
)

Set-Location $ProjectRoot

$dartFiles = Get-ChildItem -Path "lib" -Filter "*.dart" -Recurse

$newlyCompleted = @()
$stillOpen      = @()

# ── Completion markers ────────────────────────────────────────────────────────

$completionChecks = @{
    "SecurityLifecycleMixin applied to SenderScreen" = {
        (Get-Content "lib\presentation\sender\sender_screen.dart" -Raw) -match "SecurityLifecycleMixin"
    }
    "SecurityLifecycleMixin applied to DecryptScreen" = {
        (Get-Content "lib\presentation\receiver\decrypt_screen.dart" -Raw) -match "SecurityLifecycleMixin"
    }
    "compute() used for RSA decrypt" = {
        (Get-Content "lib\presentation\receiver\decrypt_screen.dart" -Raw) -match "compute\(_decryptAesKeyIsolate"
    }
    "Face ID re-enabled" = {
        $bh = Get-Content "lib\core\utils\biometric_helper.dart" -Raw
        ($bh -match "localAuth\.authenticate") -and ($bh -notmatch "return true")
    }
    "Legacy code deleted" = {
        !(Test-Path "lib\auth") -and !(Test-Path "lib\home")
    }
}

# ── Run checks ────────────────────────────────────────────────────────────────

foreach ($check in $completionChecks.GetEnumerator()) {
    $result = & $check.Value
    if ($result) {
        $newlyCompleted += "- [x] $($check.Key)"
        Write-Host "COMPLETED: $($check.Key)"
    } else {
        $stillOpen += "- [ ] $($check.Key)"
        Write-Host "OPEN:      $($check.Key)"
    }
}

Write-Host ""
Write-Host "Scan complete."
Write-Host "Completed : $($newlyCompleted.Count)"
Write-Host "Open      : $($stillOpen.Count)"
