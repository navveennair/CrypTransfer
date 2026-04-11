@echo off
echo Setting up daily test report...

schtasks /create /tn "CrypTransfer Daily Report" ^
  /tr "C:\Users\navve\projects\cryptransfer\scripts\run_tests_headless.bat" ^
  /sc daily /st 16:00 ^
  /f

echo Daily report scheduled for 4PM every day!
echo Reports will appear in Obsidian automatically.
pause
