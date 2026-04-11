---
tags: [module, ui, agent-active]
status: complete
---

# Module: UI/UX

## Responsibility
All screens, navigation, widgets, and user-facing flows for both Sender and Receiver roles.

## Files Owned
- `lib/presentation/auth/splash_screen.dart` — auth gate
- `lib/presentation/auth/login_screen.dart` — login
- `lib/presentation/auth/register_screen.dart` — registration
- `lib/presentation/home/home_screen.dart` — role hub (Send / Receive navigation)
- `lib/presentation/home/sidebar_drawer.dart` — nav drawer (profile, notifications, logout)
- `lib/presentation/home/notifications_screen.dart` — notification list
- `lib/presentation/sender/sender_screen.dart` — file select + encrypt + send stepper
- `lib/presentation/sender/transfer_progress_screen.dart` — upload progress + non-repudiation
- `lib/presentation/receiver/receiver_screen.dart` — RSA key + ready-to-receive stepper
- `lib/presentation/receiver/receiver_transfer_screen.dart` — receiver-side transfer view
- `lib/presentation/receiver/decrypt_screen.dart` — download + decrypt progress
- `lib/presentation/receiver/download_confirm_screen.dart` — file saved + path display
- `lib/presentation/session/end_session_screen.dart` — cleanup + audit log + session end
- `lib/presentation/widgets/shared_widgets.dart` — `StepCard`, `UserAvatar`, `StatusBanner`, `SecurityBadge`, `BottomSheetHandle`

## Dependencies
- `google_fonts` — Poppins typeface
- `flutter` Material — base component system
- `cloud_firestore` — real-time listeners for screen transitions

## Screen Registry
| Screen | Role | Trigger |
|--------|------|---------|
| `SplashScreen` | Both | App launch — routes to Login or Home |
| `LoginScreen` | Both | Cold start / logged out |
| `RegisterScreen` | Both | From LoginScreen |
| `HomeScreen` | Both | After login — role selection hub |
| `NotificationsScreen` | Both | From sidebar drawer |
| `SenderScreen` | Sender | "Send File" from HomeScreen |
| `TransferProgressScreen` | Sender | After file upload completes |
| `ReceiverScreen` | Receiver | "Receive File" from HomeScreen |
| `ReceiverTransferScreen` | Receiver | After accepting incoming transfer |
| `DecryptScreen` | Receiver | After download completes |
| `DownloadConfirmScreen` | Receiver | After successful decryption |
| `EndSessionScreen` | Both | After download confirmed or session cancelled |

## Shared Widgets
| Widget | Used In | Purpose |
|--------|---------|---------|
| `StepCard` | SenderScreen, ReceiverScreen | Animated step container (locked / active / done) |
| `UserAvatar` | HomeScreen, SenderScreen | Initial-based circular avatar |
| `StatusBanner` | ReceiverScreen | Animated fade-in incoming transfer banner |
| `SecurityBadge` | Multiple | "End-to-end encrypted" lock icon label |
| `BottomSheetHandle` | ReceiverScreen | Bottom sheet drag handle |

## Navigation Model
- **Login → Home**: `pushAndRemoveUntil` (clears auth stack)
- **Home → Sender/Receiver**: `push` (back returns to Home)
- **Sender → TransferProgress**: `pushReplacement` (wipes SenderScreen)
- **Decrypt → DownloadConfirm**: `pushReplacement` (save-and-wipe pattern)
- **DownloadConfirm → EndSession**: `pushReplacement`
- **EndSession → Home**: `pushAndRemoveUntil` (clears all session screens)

## TransferScreen Behaviour (CRITICAL)
- Sender's `TransferProgressScreen` launches after upload completes
- Receiver's screen transitions via Firestore `watchPendingTransfers` onSnapshot listener
- Both screens reflect live `receiverStatus` updates in real time
- Cancellation on either side → session wipe → EndSession

## Closed Mailbox UI (ReceiverScreen)
- Toggle switch calls `_onToggleReady(bool)` — not `setState` directly
- Toggle ON → `setupReceiverSession()` → generates fresh RSA keypair
- Toggle OFF → `_showCloseSessionDialog()` → orange confirmation bottom sheet
- `_sessionLocked = true` while transfer in progress → `_showSessionLockedBanner()`
- `PopScope` wraps Scaffold — wipe on back navigation
- `WidgetsBindingObserver` — auto-wipe on app pause/detach

## RSA Key Manager (ReceiverScreen)
The Key Manager is a **biometric-gated modal bottom sheet** (`_KeyManagerSheet`), NOT a
separate screen. Accessed via the `Icons.lock_outline_rounded` button in the ReceiverScreen AppBar.

- Biometric authentication required to open (`BiometricHelper.authenticate()`)
- Defined as `_KeyManagerSheet` — a private widget inside `receiver_screen.dart`
- Allows viewing sent key transfers, received keys, and step 0 key regeneration

## HomeScreen Features

### Recent Transfers List
`HomeScreen` shows a "Recent Transfers" section fed by a Firestore query:
```dart
_db.collection('transfers_log')
   .where('participants', arrayContains: uid)
   .orderBy('loggedAt', descending: true)
   .limit(10)
```
> **⚠️ Implementation Gap**: `TransferRepository.writeAuditLog()` writes `senderId`/`receiverId`
> but no `participants` array. This query always returns empty — Recent Transfers never shows data.
> Fix: add `participants: [senderId, receiverId]` to `writeAuditLog()`.

### Overlay Notification Banner (`_NotifBanner`)
`HomeScreen` uses a `_NotifBanner` `OverlayEntry` (not a `MaterialBanner`) for in-app alerts:
- Driven by `NotificationService.latestUnreadStream(uid)`
- Auto-dismisses after **5 seconds** via `Timer`
- Tapping routes by notification type:
  - `rsa_key_received` → pushes `SenderScreen` (key is ready to use for sending)
  - `file_received` → pushes `ReceiverScreen` (incoming file awaiting pickup)
- `_NotifBellButton` in AppBar shows unread count badge (`unreadCountStream`); count > 9 displays "9+"

## Stepper Pattern
Both `SenderScreen` and `ReceiverScreen` use the sequential stepper pattern:
- Each step is a `StepCard` widget
- Steps below current are opacity 0.4 (`AnimatedOpacity`) — visually locked
- Step completion boolean gates the next step's `onPressed`
- `StepCard` shows green border + checkmark when `done: true`, purple when active

## Current Status
✅ SplashScreen auth gate done  
✅ Login + Register with real-time validation done  
✅ HomeScreen role hub done  
✅ SenderScreen stepper (file select → encrypt → send) done  
✅ TransferProgressScreen with live upload progress done  
✅ ReceiverScreen Closed Mailbox stepper done  
✅ DecryptScreen save-and-suicide pattern done  
✅ DownloadConfirmScreen with file path + clipboard copy done  
✅ EndSessionScreen with Firebase cleanup done  
✅ Shared widget library (`StepCard`, `UserAvatar`, `StatusBanner`, `SecurityBadge`) done  

## Agent Instructions
1. Keep UI consistent with Material Design 3
2. ReceiverScreen toggle MUST go through `_onToggleReady` — never setState directly
3. TransferProgressScreen MUST use Firestore listener for `receiverStatus` — not polling
4. `DecryptScreen` MUST zero all crypto buffers before navigating away
5. All session screens MUST use `SecurityLifecycleMixin`
6. Update this doc after adding or modifying any screen

## Open Tasks
- [ ] Receiver stepper same look as sender stepper
- [ ] 3D buttons across all screens
- [ ] Polish UI for viva demo
- [ ] Fix Recent Transfers list — add `participants` field to `writeAuditLog()` (currently always empty)
