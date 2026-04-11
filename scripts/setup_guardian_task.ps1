# Run this ONCE as Administrator to register the scheduled task.
# Usage: powershell -ExecutionPolicy Bypass -File scripts\setup_guardian_task.ps1

$taskName   = "CrypTransfer Silent Guardian"
$scriptPath = "C:\Users\navve\projects\cryptransfer\scripts\launch_guardian.bat"

# Remove old task if it exists
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

# Trigger: daily at 12:00 PM
$trigger = New-ScheduledTaskTrigger -Daily -At "12:00PM"

# Action: run the batch launcher hidden
$action = New-ScheduledTaskAction `
    -Execute "cmd.exe" `
    -Argument "/c `"$scriptPath`""

# Settings: tolerant of missed runs, retry on failure
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 5) `
    -RunOnlyIfNetworkAvailable `
    -StartWhenAvailable

# Principal: current user, highest privileges
$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -RunLevel Highest `
    -LogonType InteractiveToken

Register-ScheduledTask `
    -TaskName  $taskName `
    -Trigger   $trigger `
    -Action    $action `
    -Settings  $settings `
    -Principal $principal `
    -Force

Write-Host "Guardian task created!"
Write-Host "Runs daily at 12:00 PM"
Write-Host "Reports: $env:USERPROFILE\ObsidianVault\CrypTransfer\DailyReports\"
