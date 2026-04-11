@echo off
cd C:\Users\navve\projects\cryptransfer

flutter test test/module_tests/ test/security/ --reporter=json > test_results.json 2>&1
dart scripts/write_obsidian_report.dart >> scripts\test_run.log 2>&1

exit /b 0
