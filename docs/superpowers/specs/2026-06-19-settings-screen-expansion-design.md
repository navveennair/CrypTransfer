# Settings Screen Expansion — Design

**Date:** 2026-06-19
**Status:** Approved, ready for implementation plan

## Problem

`lib/presentation/settings/settings_screen.dart` currently has exactly one
section ("General → Appearance"). Several already-built capabilities —
account info/logout, notification history, admin dashboard access — live
only in `sidebar_drawer.dart`, with no presence in Settings at all. This
expands Settings into the actual home for account-level actions, and trims
the sidebar drawer to navigation-only items.

## Scope

In scope:
- Add an **Account** section to Settings (read-only profile card + Logout).
- Add a **Notifications** section to Settings (shortcut to the existing
  `NotificationsScreen`, with a live unread-count badge).
- Add an **Admin** section to Settings (shortcut to the existing
  `/admin-dashboard` route, visible only to admins).
- Remove the Logout item and the Admin Dashboard item from
  `sidebar_drawer.dart` (superseded by the above).
- Rename the sidebar's "Find Friends" label to "Connections" — label only,
  no functional or routing change.

Explicitly out of scope (considered and deferred during brainstorming):
- **Biometric/PIN authentication toggle.** `BiometricHelper.authenticate()`
  is called unconditionally today at 3 sites (`rsa_key_manager_screen.dart:30`,
  `receiver_screen.dart:499`, `sender_screen.dart:275`) and stays that way —
  biometric auth remains mandatory. `AuthMethodService`
  (`lib/core/services/auth_method_service.dart`) remains unused/dead code;
  no PIN entry UI is built. This was deliberately dropped from scope, not
  forgotten.
- **A dedicated "Manage Connections" shortcut in Settings.** Decided against;
  the sidebar's renamed "Connections" item remains the only entry point.
- Any new backend/repository methods — every data source used below already
  exists and is in production use elsewhere.

## Architecture

`SettingsScreen` stays a `StatelessWidget` (matching `SidebarDrawer`'s
existing pattern: instantiate `AuthRepository()` in `build()`, drive
everything off `StreamBuilder`s — no new state management). It grows from
one section to four:

1. **General** (unchanged) — Appearance row, drill-down to
   `AppearanceSubScreen`.
2. **Account** (new, inline — no drill-down) — profile card
   (username/email/phone/joined date) + Logout button.
3. **Notifications** (new, inline) — single shortcut row with a live
   unread-count badge, pushes the existing `NotificationsScreen`.
4. **Admin** (new, inline, conditional on `isAdmin`) — single shortcut row,
   pushes the existing `/admin-dashboard` named route.

Account was deliberately kept inline rather than as its own drill-down
sub-screen (rejected alternative: mirror `AppearanceSubScreen` exactly) —
it's small enough that an extra tap to see "which account am I logged into"
isn't worth the navigation depth or the extra screen class.

## Components & Data Flow

- **Account card**: one `StreamBuilder<UserModel?>` on
  `authRepo.streamUserProfile(uid)` feeds username, email, phone, and a
  formatted `createdAt`. Use `package:intl`'s `DateFormat('MMM d, yyyy')`
  (already a direct dependency, imported in
  `lib/presentation/admin/widgets/security_pulse_feed.dart`) — e.g.
  "Jun 19, 2026". This same stream's `isAdmin` field also gates the Admin
  section — one subscription serves both, avoiding a duplicate Firestore
  listener.
- **Logout**: the existing confirmation-dialog + `authRepo.logout()` +
  `pushAndRemoveUntil(LoginScreen)` block moves verbatim from
  `sidebar_drawer.dart:153-222` into `settings_screen.dart`. No behavior
  change — `AuthRepository.logout()` has no try/catch today
  (`auth_repository.dart:235-238`) and none is added; this isn't the place
  to introduce new error handling.
- **Notifications row**: `StreamBuilder<int>` on
  `NotificationService.unreadCountStream(uid)` drives a small circular
  count badge in the `ListTile`'s `trailing`, styled after the existing
  badge in `home_screen.dart`'s `_NotifBellButton` (lines 611-621 — a
  `cs.error`-colored circle Container). No shared badge widget currently
  exists to extract; this is a new small Container built the same way,
  not a reused component. Tapping navigates to the existing
  `NotificationsScreen` via `MaterialPageRoute`.
- **Admin row**: reuses `Navigator.pushNamed(context, '/admin-dashboard')`
  exactly as the sidebar does today. The route stays wrapped in `AdminGuard`
  (`main.dart:43`) — this is a navigation convenience, not a new trust
  boundary; the UI-level `isAdmin` check is defense-in-depth on top of the
  route guard, same as the sidebar's existing pattern.
- **Sidebar cleanup**: remove the Admin Dashboard `_DrawerItem` + its
  `StreamBuilder` wrapper (`sidebar_drawer.dart:117-135`), remove the
  Logout `_DrawerItem` + its confirmation dialog
  (`sidebar_drawer.dart:153-222`), rename the Find Friends label string to
  "Connections" (`sidebar_drawer.dart:94`, same `onTap`/target). Drop the
  `login_screen.dart` import from `sidebar_drawer.dart` if nothing else in
  that file references it after Logout moves out.

## Error Handling

No new failure modes are introduced. Every data source
(`streamUserProfile`, `unreadCountStream`, `logout()`) is already in
production use elsewhere with its current error behavior (or deliberate
lack thereof) unchanged. The only defensive check is the existing
`if (user != null)` guard (copied from the sidebar's own pattern) around the
profile/admin `StreamBuilder`, so Settings doesn't crash if somehow reached
while signed out.

## Testing

This is a UI composition change with no new business logic — no new
automated tests are added. Existing `flutter analyze` and the security test
suite (which doesn't touch Settings) remain the safety net. Manual
verification in the running app covers:

- Account card shows correct live data (username/email/phone/joined date).
- Logout still prompts for confirmation, signs out, and redirects to
  `LoginScreen` correctly from its new location in Settings.
- Notifications badge reflects unread count and navigates to
  `NotificationsScreen` correctly.
- Admin row appears only for an admin account and navigates to
  `/admin-dashboard` correctly; does not appear for non-admin accounts.
- Sidebar no longer shows Admin Dashboard or Logout, but still shows
  "Connections" (renamed from "Find Friends") routing to
  `FindFriendsScreen` unchanged.
