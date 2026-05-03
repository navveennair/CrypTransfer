# DevOps & Automation

This module documents the CI/CD and security monitoring scripts for CrypTransfer.

## Security Guardian
- **Script**: `scripts/silent_guardian.ps1`
- **Role**: Headless monitor that runs periodically to verify the security state of the `lib/` directory.
- **Enforcement**:
  - Verifies that `SecurityLifecycleMixin` is active in `SenderScreen` and `DecryptScreen`.
  - Checks for the "Kill Switch" implementation in `EncryptionService` and `ReceiverScreen`.
  - Ensures `participants` audit logging is present in `TransferRepository`.
  - Scans for hardcoded keys or dangerous `debugPrint` statements.
- **Output**: Generates a Daily Report in the Obsidian vault and triggers a security audit.

## Status Tracking
- **Script**: `scripts/update_status.ps1`
- **Role**: Scans the project for feature completion markers defined in `CLAUDE.md`.
- **Logic**: Uses regex to verify implementation details like `compute()` usage for RSA decryption and Face ID re-enablement.

## Build Configuration
- **Android**: Managed via `android/build.gradle.kts` and `android/app/build.gradle.kts`.
- **Security**: ProGuard/R8 rules are configured to obfuscate security-sensitive code paths.
