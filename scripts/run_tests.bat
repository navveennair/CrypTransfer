@echo off
echo ============================================
echo CrypTransfer Test Suite
echo Started: %date% %time%
echo ============================================
echo.

cd C:\Users\navve\projects\cryptransfer

echo Running Flutter tests...
flutter test test/module_tests/ test/security/ ^
  --reporter=json > test_results.json 2>&1

echo.
echo Writing report to Obsidian...
dart scripts/write_obsidian_report.dart >> ^
  scripts\test_run.log 2>&1

echo.
echo ============================================
echo Completed: %date% %time%
echo ============================================

exit /b 0
