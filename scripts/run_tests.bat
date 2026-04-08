@echo off
echo Running CrypTransfer Test Suite...
echo.
cd C:\Users\navve\projects\cryptransfer
flutter test test/module_tests/ test/security/ --reporter=json > test_results.json
echo.
echo Writing report to Obsidian...
dart scripts/write_obsidian_report.dart
echo.
echo Done! Check Obsidian for full report.
pause
