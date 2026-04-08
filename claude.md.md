Create a CLAUDE.md file at the root of the project:
C:\Users\navve\projects\cryptransfer\CLAUDE.md

This file is read automatically by Claude Code
on every session. It must contain current project
state so no re-explanation is needed.

Write the following content to CLAUDE.md:

---

# CrypTransfer — Claude Code Session Context

## Project Identity
- App: CrypTransfer (Flutter mobile FYP)
- Student: Navveen Nair | UTM | A22EC0092
- Supervisor: Dr. Rashidah Binti Kadir
- Deadline: June 2025 (PSM2)
- Repo: C:\Users\navve\projects\cryptransfer

## Stack
- Flutter 3.41.4 + Dart
- Firebase (Auth, Firestore, Storage) — singapore region
- PointyCastle (AES-256-GCM + RSA-2048-OAEP)
- flutter_secure_storage (Android Keystore)
- local_auth (Face ID — currently bypassed for testing)
- file_picker, path_provider, google_fonts

## Architecture (Clean)
lib/
├── core/constants/ errors/ utils/
├── data/models/ repositories/ services/
│   ├── encryption_service.dart ← ALL crypto here
│   ├── auth_repository.dart
│   ├── transfer_repository.dart
│   └── key_repository.dart
└── presentation/
    ├── auth/ (splash, login, register)
    ├── home/ (home, notifications, sidebar)
    ├── sender/ (sender_screen, transfer_progress)
    ├── receiver/ (receiver_screen, decrypt_screen)
    └── session/ (end_session_screen)

## Security Model
- RSA keypair: per-session, wiped on app launch
  AND after session completes/fails
- Private key: flutter_secure_storage key='rsa_private_key'
- Public key: Firestore users/{uid}/publicKey
- AES key: memory only, zeroed after use
- TLS 1.3: automatic via Firebase (satisfies SD007)
- Face ID: bypassed (authenticate() returns true)
  RE-ENABLE before viva

## Firestore Collections
- users: {uid, username, email, phone, publicKey,
          isAdmin, isDisabled, isReadyToReceive}
- friend_requests: {senderId, receiverId, 
                    status, createdAt}
- rsa_key_transfers: {fromUserId, toUserId,
                      publicKey, sentAt, transferId}
- transfers: {senderId, receiverId, encryptedAESKey,
              encryptedFileUrl, fileName, fileSize,
              iv, status, sessionActive, createdAt}
- notifications: {toUserId, fromUsername, type,
                  message, transferId, read}
- transfers_log: {senderId, receiverId, fileName,
                  transferDate, status}

## Transfer Flow
1. Receiver generates RSA keypair
2. Establishes connection with Sender
3. Sends public key → rsa_key_transfers
4. Sender notified via notifications collection
5. Sender selects receiver explicitly (Step 0)
6. Sender picks file → AES-256-GCM encrypt
7. RSA-OAEP wraps AES key
8. Upload to Firebase Storage
9. Receiver notified → decrypt_screen
10. RSA unwrap → AES decrypt → save/delete
11. End Session → ALL data wiped
12. Audit log written to transfers_log

## Session States
pending → ready → accepted → decrypted → completed
                           ↘ cancelled/expired

## Current Build Status (update this after each session)
- Flutter analyze: 1 info (key_repository.dart:323)
- Zero errors, zero warnings
- Both emulators running: 5554 (Sender) + 5556 (Receiver)
- Last working feature: File sent + received + decrypted

## Known Open Issues (update after each fix)
- [ ] CRITICAL: Isolate.run() crash in decrypt_screen.dart
      Fix: Replace with compute() + top-level function
- [ ] DownloadConfirmScreen not built yet
- [ ] ReceiverTransferScreen not built yet  
- [ ] Face ID disabled for testing — re-enable before viva
- [ ] RSA public key not always reaching sender correctly
- [ ] Loading indicators missing on some screens
- [ ] Unit tests not written yet

## Completed Features
- [x] Auth (login, register, splash router)
- [x] RSA-2048 keypair generation on register
- [x] Key wipe on app launch
- [x] Sender flow: Step 0-4 complete
- [x] Receiver flow: RSA KeyGen, Establish Connection
- [x] Ready to Receive toggle
- [x] Notifications system (bell + banner)
- [x] File encryption AES-256-GCM working
- [x] File upload to Firebase Storage working
- [x] Transfer record in Firestore
- [x] Receiver listener for incoming transfers
- [x] Session integrity (cancel flow)
- [x] End session + cleanup
- [x] Admin panel (4 screens)
- [x] Clean architecture migration complete
- [x] Legacy dead code deleted

## Week Plan
Week 1 ✅ Auth + RSA Key Generation
Week 2 ✅ File Encryption + Send Flow  
Week 3 ✅ Receive + Decrypt + Session
Week 4 ⏳ Admin + Polish + Testing

## DO NOT
- Use AuthService (deleted) → use AuthRepository
- Use ConnectionService (deleted) → use KeyRepository
- Write crypto logic in screens → use EncryptionService
- Write Firestore calls in screens → use repositories
- Store private key anywhere except flutter_secure_storage
- Upload plaintext files to Firebase Storage

## ALWAYS
- Run flutter analyze after changes
- Update Known Open Issues section above
- Update Completed Features when done
- Keep crypto in EncryptionService only
- Keep Firebase calls in repositories only
- Follow purple Material Design 3 theme
- Test on both emulators after major changes

## Obsidian Vault Path
C:\Users\navve\ObsidianVault\CrypTransfer\

## Test Reports Path  
C:\Users\navve\ObsidianVault\CrypTransfer\TestReports\

---

After creating CLAUDE.md also create:

.claude/commands/update-status.md:
When user says "update status":
1. Read current CLAUDE.md
2. Check git log for recent commits
3. Run flutter analyze
4. Update Known Open Issues
5. Update Completed Features
6. Write updated CLAUDE.md

.claude/commands/daily-report.md:
When user says "daily report":
1. Read CLAUDE.md for context
2. Check git diff since yesterday
3. Run flutter analyze
4. Generate report in Obsidian:
   C:\Users\navve\ObsidianVault\CrypTransfer\
   DailyReports\{date}_report.md
5. Format: changes made, issues fixed,
   issues remaining, next steps

.claude/commands/run-tests.md:
When user says "run tests":
1. Read CLAUDE.md for context
2. Run flutter test
3. Write results to Obsidian TestReports
4. Report summary here
5. Fix any failures found
   
WHAT WAS FIXED 
Move these from Open Issues to Completed:
- [x] Isolate.run() crash fixed in decrypt_screen
- [x] DownloadConfirmScreen built
- [x] ReceiverTransferScreen built
- [x] Loading indicators added (sender + receiver)
- [x] Save path displayed after file download

Update Known Open Issues to:
- [ ] Face ID disabled — re-enable before viva
- [ ] RSA public key not always reaching sender
- [ ] Unit tests not written yet
- [ ] Admin panel needs testing
- [ ] End-to-end test on both emulators needed

Update Completed Features to add:
- [x] DownloadConfirmScreen with save path display
- [x] ReceiverTransferScreen with animation
- [x] compute() based RSA decrypt (no UI freeze)
- [x] Loading indicators on all async operations