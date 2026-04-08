# Run Tests Command

When user says "run tests" or "test":
1. Execute: flutter test test/ --reporter=expanded
2. Check for failures
3. Run: dart scripts/write_obsidian_report.dart
4. Report summary to user
5. If failures: propose fixes, ask confirmation
