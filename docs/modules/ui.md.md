---
tags: [module, ui, agent-active]
status: in-progress
---
---
tags: [module, ui, agent-active]
status: in-progress
---

# Module: UI/UX

## Responsibility
All screens, navigation, and user-facing flows for both Sender and Receiver roles.

## Files Owned
- lib/src/features/screens/
- lib/src/features/widgets/

## Dependencies
- Flutter Material
- Firebase Firestore (real-time listeners for screen transitions)

## Screen Registry
| Screen | Role | Trigger |
|---|---|---|
| RoleSelectionScreen | Both | On login |
| SenderHomeScreen | Sender | After role selected |
| ReceiverHomeScreen | Receiver | After role selected |
| TransferScreen (Sender) | Sender | Immediately after file is marked "Sent" |
| TransferScreen (Receiver) | Receiver | Firestore listener detects incoming transfer |
| DecryptScreen | Receiver | After file is fully received |
| DownloadConfirmScreen | Receiver | After successful decryption |

## TransferScreen Behaviour (CRITICAL)
- Sender's TransferScreen launches **immediately** when file is marked "Sent"
- Receiver's TransferScreen launches **simultaneously** via Firestore `onSnapshot` listener
- Receiver's Transfer Session **only initializes** when file receipt is confirmed
- Both screens must reflect **live transfer progress** in real-time
- If transfer is cancelled on either side — session wipes immediately

## Decrypt & Download Flow
- After full file receipt, Receiver is navigated to DecryptScreen automatically
- Decryption runs in background — UI shows progress indicator
- On success, file is saved to **local device storage** (Downloads folder)
- DownloadConfirmScreen shows file name, size, and save location
- File must be accessible **outside the app** after download

## Current Status
✅ Role selection screen done
✅ Transfer progress screen done
✅ Decrypt screen done
🔄 TransferScreen simultaneous trigger (Sender + Receiver) — in progress
🔄 Download confirmation screen — pending
🔄 Local storage save confirmation — pending

## Agent Instructions
1. Keep UI consistent with Material Design
2. TransferScreen must ALWAYS be triggered via Firestore listener — never manually navigated
3. Receiver must NEVER enter TransferScreen before file receipt is confirmed
4. DecryptScreen must auto-navigate after successful file receipt — no manual trigger
5. DownloadConfirmScreen must display file path so user knows where file is saved
6. Update this doc after adding or modifying any screen

## Open Tasks
- [ ] Verify TransferScreen simultaneous launch on both Sender and Receiver
- [ ] Implement DownloadConfirmScreen with file path display
- [ ] Confirm decrypted file saves correctly to Downloads folder
- [ ] Add progress indicator on DecryptScreen during decryption
- [ ] Polish UI for viva demo
- [ ] Add loading indicators where missing