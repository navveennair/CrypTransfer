@echo off
powershell.exe -WindowStyle Hidden ^
  -NonInteractive ^
  -ExecutionPolicy Bypass ^
  -File "C:\Users\navve\projects\cryptransfer\scripts\silent_guardian.ps1" ^
  >> "C:\Users\navve\projects\cryptransfer\report_error.log" 2>&1
exit /b 0
