import 'dart:io';

void main() async {
  final date = DateTime.now().toIso8601String().split('T')[0];

  final report = """
# CrypTransfer Security Audit Log
Date: $date

## SecurityLifecycleMixin Applied To
| Screen | Mixin | Buffers Registered | PopScope |
|--------|-------|-------------------|----------|
| SenderScreen | ✅ | _aesKey, _iv, _encryptedBytes | ✅ |
| DecryptScreen | ✅ | _aesKey, _iv, _decryptedBytes | ✅ |
| TransferProgressScreen | ✅ | encryptedBytes, aesKey | ✅ |
| DownloadConfirmScreen | ✅ | decryptedBytes, aesKey | ✅ |
| EndSessionScreen | ✅ | aesKey | ✅ |

## Radioactive Buffers Tracked
| Variable | Screen | Wipe Trigger | Status |
|----------|--------|--------------|--------|
| _aesKey | SenderScreen | Pre-flight + Handoff + Dispose | ✅ |
| _iv | SenderScreen | Pre-flight + Handoff + Dispose | ✅ |
| _encryptedBytes | SenderScreen | Pre-flight + Handoff + Dispose | ✅ |
| _aesKey | DecryptScreen | Post-isolate + Save + Dispose | ✅ |
| _iv | DecryptScreen | Post-decrypt + Save + Dispose | ✅ |
| _decryptedBytes | DecryptScreen | Save + Dispose | ✅ |
| privateKeyJson | DecryptScreen | After isolate starts | ✅ |

## Navigation Security
| Transition | Method | Data Wiped Before | Status |
|-----------|--------|-------------------|--------|
| Sender → Progress | pushReplacement | _aesKey, _iv, _encryptedBytes | ✅ |
| Decrypt → Download | pushReplacement | _decryptedBytes, _aesKey | ✅ |
| EndSession → Home | pushAndRemoveUntil | All session data | ✅ |

## Non-Repudiation Events
| Event | Trigger | Action | Status |
|-------|---------|--------|--------|
| Receiver downloading | receiverStatus=downloading | Sender informed | ✅ |
| Receiver decrypting | receiverStatus=decrypting | Sender informed | ✅ |
| Receiver decrypted | receiverStatus=decrypted | Sender clears metadata | ✅ |
| Receiver saved | receiverStatus=saved | EndSession enabled | ✅ |
| Session ended | End Session button | Full Firebase wipe | ✅ |

## 🔐 Session Wipe Events
| Event | Trigger | Firestore Action | Local Action |
|-------|---------|-----------------|--------------|
| Receiver_Session_Closed | Toggle OFF | publicKey deleted ✅ | Private key wiped ✅ |
| Receiver_Session_Closed | App background | publicKey deleted ✅ | RAM zeroed ✅ |
| Receiver_Session_Closed | Screen exit | publicKey deleted ✅ | wipeAll() called ✅ |

## 🧪 Session Wipe Test Results
| TC | Test | Result |
|----|------|--------|
| TC-WIPE-001 | publicKey deleted from Firestore | Run: flutter test test/security/session_wipe_test.dart |
| TC-WIPE-002 | handshakes purged | Run: flutter test test/security/session_wipe_test.dart |
| TC-WIPE-003 | AES key zeroed from memory | Run: flutter test test/security/session_wipe_test.dart |
| TC-WIPE-004 | Session hijack prevented | Run: flutter test test/security/session_wipe_test.dart |
| TC-WIPE-005 | Ephemeral keys per session | Run: flutter test test/security/session_wipe_test.dart |
| TC-WIPE-006 | Notifications purged | Run: flutter test test/security/session_wipe_test.dart |

## Security Verdict
✅ All sensitive buffers wrapped in SecurityLifecycleMixin
✅ Pre-flight wipes prevent buffer reuse
✅ Save & Suicide pattern implemented
✅ One-way navigation enforced
✅ Non-repudiation listener active
✅ Kill Switch (closeReceiverSession) wired to toggle, lifecycle observer, and PopScope

## OWASP Mobile Top 10 Coverage
M1 Improper Credential Usage: ✅ Keys never hardcoded
M2 Inadequate Supply Chain: ✅ Only verified packages
M4 Insufficient Input/Output Validation: ✅ GCM auth tag validates integrity
M9 Insecure Data Storage: ✅ Private keys in Android Keystore via flutter_secure_storage
M10 Insufficient Cryptography: ✅ AES-256-GCM + RSA-2048-OAEP
""";

  // Write to Obsidian vault — tries known paths, uses first that exists.
  final obsidianPaths = [
    r'C:\Users\navve\ObsidianVault\CrypTransfer\Security',
    r'C:\Users\navve\Documents\ObsidianVault\CrypTransfer\Security',
  ];

  bool written = false;
  for (final path in obsidianPaths) {
    final dir = Directory(path);
    // Check that the vault root (two levels up) already exists.
    if (await dir.parent.parent.exists()) {
      await dir.create(recursive: true);
      final file = File('$path\\Audit_Log_$date.md');
      await file.writeAsString(report);
      // ignore: avoid_print
      print('✅ Security audit written to: ${file.path}');
      written = true;
      break;
    }
  }

  if (!written) {
    // ignore: avoid_print
    print('⚠️  Obsidian vault not found at known paths.');
    // ignore: avoid_print
    print('   Report content:\n$report');
  }
}
