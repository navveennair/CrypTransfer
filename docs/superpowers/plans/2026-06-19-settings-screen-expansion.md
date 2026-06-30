# Settings Screen Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the in-app Settings screen with Account, Notifications, and Admin sections (currently only scattered in the sidebar drawer or missing entirely), and trim the sidebar drawer down to navigation-only items.

**Architecture:** `SettingsScreen` stays a `StatelessWidget`. A single `StreamBuilder<UserModel?>` on the current user's profile feeds both the new Account card and the conditional Admin section (one Firestore subscription, not two). Notifications is a sibling section inside the same builder so visual ordering (Account → Notifications → Admin) matches the approved spec while still sharing the one subscription. `sidebar_drawer.dart` loses its Logout and Admin Dashboard items and gets one label rename.

**Tech Stack:** Flutter/Dart, `cloud_firestore` (via existing `AuthRepository`/`NotificationService`), `package:intl` for date formatting, no new packages.

## Global Constraints

- No new automated tests are added — verification is `flutter analyze` (expect "No issues found!") plus manual in-app checks, per the spec's deliberate decision (see spec's Testing section).
- Biometric/PIN authentication toggle is explicitly out of scope. Do not touch `BiometricHelper`, `AuthMethodService`, or their 3 call sites (`rsa_key_manager_screen.dart:30`, `receiver_screen.dart:499`, `sender_screen.dart:275`).
- No new backend/repository methods. Reuse `AuthRepository.currentUid`, `.currentUser`, `.streamUserProfile(uid)`, `.logout()`; `NotificationService.unreadCountStream(uid)`; `UserModel` fields — all exactly as they exist today.
- Admin route stays `/admin-dashboard`, already registered in `main.dart:43` wrapped in `AdminGuard` — do not change route registration, only which screen links to it.
- Joined-date formatting: `DateFormat('MMM d, yyyy')` from `package:intl/intl.dart` (e.g. "Jun 19, 2026"). Missing/null values render as `'—'`, matching the existing fallback convention in `admin_dashboard.dart`.
- "Find Friends" → "Connections" is a label-only rename — the `onTap` target (`FindFriendsScreen`) does not change.

---

### Task 1: Account section in Settings (profile card + Logout), remove Logout from sidebar

**Files:**
- Modify: `lib/presentation/settings/settings_screen.dart`
- Modify: `lib/presentation/home/sidebar_drawer.dart`

**Interfaces:**
- Produces: `final uid = authRepo.currentUid;` local variable (`String?`) in `SettingsScreen.build()`, and a `StreamBuilder<UserModel?>` block whose `builder` returns a `Column` with a `children` list ending in `_AccountSection(...)`. Task 2 and Task 3 insert further entries into that same `children` list, after this task's last entry.
- Produces: `_AccountSection({required UserModel? profile, required String? authEmail, required AuthRepository authRepo})` — a private widget, not called by later tasks directly, but its presence is what later tasks' diffs are anchored after.

- [ ] **Step 1: Add the Account section to `settings_screen.dart`**

Add these imports at the top of `lib/presentation/settings/settings_screen.dart` (after the existing `shared_widgets.dart` import):

```dart
import 'package:intl/intl.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../auth/login_screen.dart';
```

In `SettingsScreen.build()`, change:

```dart
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
```

to:

```dart
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final authRepo = AuthRepository();
    final uid = authRepo.currentUid;
    return Scaffold(
```

Then, immediately after the closing of the existing "General" `GlassContainer` (the Appearance `ListTile`) — i.e. replace:

```dart
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AppearanceSubScreen()),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

with:

```dart
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AppearanceSubScreen()),
                  ),
                ),
              ),
            ),

            if (uid != null)
              StreamBuilder<UserModel?>(
                stream: authRepo.streamUserProfile(uid),
                builder: (context, snapshot) {
                  final profile = snapshot.data;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      Text(
                        'Account',
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _AccountSection(
                        profile: profile,
                        authEmail: authRepo.currentUser?.email,
                        authRepo: authRepo,
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
```

Then add these two new widget classes at the end of the file (after the existing `_ThemeOption` class):

```dart
class _AccountSection extends StatelessWidget {
  final UserModel? profile;
  final String? authEmail;
  final AuthRepository authRepo;

  const _AccountSection({
    required this.profile,
    required this.authEmail,
    required this.authRepo,
  });

  String _formatJoined(DateTime? date) {
    if (date == null) return '—';
    return DateFormat('MMM d, yyyy').format(date);
  }

  Future<void> _handleLogout(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final nav = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        content: GlassContainer(
          padding: const EdgeInsets.all(24),
          borderRadius: 28,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout_rounded, size: 48, color: cs.error),
              const SizedBox(height: 16),
              Text(
                'Logout',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Are you sure you want to logout?',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: CrypButton(
                      label: const Text('Cancel'),
                      onPressed: () => Navigator.pop(ctx, false),
                      color: cs.onSurfaceVariant,
                      height: 44,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CrypButton(
                      label: const Text('Logout'),
                      color: cs.error,
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      await authRepo.logout();
      if (nav.context.mounted) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final username = (profile?.username.isNotEmpty ?? false) ? profile!.username : '—';
    final email = (profile?.email.isNotEmpty ?? false) ? profile!.email : (authEmail ?? '—');
    final phone = (profile?.phone.isNotEmpty ?? false) ? profile!.phone : '—';
    final joined = _formatJoined(profile?.createdAt);

    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AccountInfoRow(label: 'Username', value: username),
          const Divider(height: 20),
          _AccountInfoRow(label: 'Email', value: email),
          const Divider(height: 20),
          _AccountInfoRow(label: 'Phone', value: phone),
          const Divider(height: 20),
          _AccountInfoRow(label: 'Joined', value: joined),
          const SizedBox(height: 20),
          CrypButton(
            label: const Text('Logout'),
            icon: const Icon(Icons.logout_rounded, size: 18),
            color: cs.error,
            onPressed: () => _handleLogout(context),
          ),
        ],
      ),
    );
  }
}

class _AccountInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _AccountInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        Flexible(
          child: Text(
            value,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Run static analysis to verify Step 1 compiles clean**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Remove the Logout item from `sidebar_drawer.dart`**

In `lib/presentation/home/sidebar_drawer.dart`, remove the now-unused import:

```dart
import '../auth/login_screen.dart';
```

Then replace (the `Spacer`/`Divider`/`SizedBox(8)` separator plus the entire Logout `_DrawerItem` block, down to the final bottom-padding `SizedBox`):

```dart
            const Spacer(),
            const Divider(height: 1, indent: 24, endIndent: 24),
            const SizedBox(height: 8),

            _DrawerItem(
              icon: Icons.logout_rounded,
              label: 'Logout',
              color: cs.error,
              onTap: () async {
                final nav = Navigator.of(context);
                nav.pop(); // close drawer

                final confirmed = await showDialog<bool>(
                  context: nav.context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: const EdgeInsets.all(24),
                    content: GlassContainer(
                      padding: const EdgeInsets.all(24),
                      borderRadius: 28,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.logout_rounded, size: 48, color: cs.error),
                          const SizedBox(height: 16),
                          Text(
                            'Logout',
                            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Are you sure you want to logout?',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 32),
                          Row(
                            children: [
                              Expanded(
                                child: CrypButton(
                                  label: const Text('Cancel'),
                                  onPressed: () => Navigator.pop(ctx, false),
                                  color: cs.onSurfaceVariant,
                                  height: 44,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: CrypButton(
                                  label: const Text('Logout'),
                                  color: cs.error,
                                  onPressed: () => Navigator.pop(ctx, true),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );

                if (confirmed == true) {
                  await authRepo.logout();
                  if (nav.context.mounted) {
                    nav.pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 20),
          ],
```

with:

```dart
            const SizedBox(height: 20),
          ],
```

- [ ] **Step 4: Run static analysis to verify the sidebar still compiles clean**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Manual verification**

Run the app (`flutter run`), log in, open Settings (sidebar → Settings). Confirm:
- An "Account" section appears below "General", showing your test account's Username, Email, Phone, and Joined date (format "MMM d, yyyy", e.g. "Jun 19, 2026").
- Tapping "Logout" shows the confirmation dialog; tapping "Cancel" dismisses it with no effect; tapping "Logout" again signs out and returns you to the Login screen.
- Open the sidebar drawer: confirm the Logout item is gone, and the drawer's bottom padding still looks correct (no leftover empty divider).

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/settings/settings_screen.dart lib/presentation/home/sidebar_drawer.dart
git commit -m "feat(settings): add Account section, move Logout out of sidebar"
```

---

### Task 2: Notifications shortcut section in Settings

**Files:**
- Modify: `lib/presentation/settings/settings_screen.dart`

**Interfaces:**
- Consumes: `uid` (promoted to non-null `String` inside the `if (uid != null)` block from Task 1) and the `StreamBuilder`'s `children` list, inserting after the `_AccountSection(...)` entry Task 1 added.
- Produces: `_NotificationsSection({required String uid})`; the `children` list now ends with `_NotificationsSection(uid: uid)`. Task 3 inserts after this.

- [ ] **Step 1: Add the Notifications section to `settings_screen.dart`**

Add these imports (after the imports added in Task 1):

```dart
import '../../core/utils/notification_service.dart';
import '../home/notifications_screen.dart';
```

In the `children` list inside the `StreamBuilder`'s `builder` (added in Task 1), change:

```dart
                      const SizedBox(height: 12),
                      _AccountSection(
                        profile: profile,
                        authEmail: authRepo.currentUser?.email,
                        authRepo: authRepo,
                      ),
                    ],
                  );
                },
              ),
```

to:

```dart
                      const SizedBox(height: 12),
                      _AccountSection(
                        profile: profile,
                        authEmail: authRepo.currentUser?.email,
                        authRepo: authRepo,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Notifications',
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _NotificationsSection(uid: uid),
                    ],
                  );
                },
              ),
```

Then add this new widget class at the end of the file (after `_AccountInfoRow`):

```dart
class _NotificationsSection extends StatelessWidget {
  final String uid;

  const _NotificationsSection({required this.uid});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GlassContainer(
      padding: EdgeInsets.zero,
      // Transparent Material so the ListTile's ink splash paints above
      // GlassContainer's coloured box (otherwise it's hidden + asserts).
      child: Material(
        type: MaterialType.transparency,
        child: StreamBuilder<int>(
          stream: NotificationService.unreadCountStream(uid),
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            return ListTile(
              leading: Icon(Icons.notifications_none_rounded, color: cs.primary),
              title: Text(
                'Notifications',
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'View notification history',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (count > 0)
                    Container(
                      padding: const EdgeInsets.all(2),
                      margin: const EdgeInsets.only(right: 8),
                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                      decoration: BoxDecoration(
                        color: cs.error,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Manual verification**

Run the app, open Settings. Confirm:
- A "Notifications" section appears below "Account", with a bell icon, the subtitle "View notification history", and (if you have unread notifications) a small red count badge before the chevron.
- Tapping the row navigates to the existing Notifications screen (same screen reachable from the home screen's bell icon).

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/settings/settings_screen.dart
git commit -m "feat(settings): add Notifications shortcut section"
```

---

### Task 3: Admin Dashboard shortcut in Settings, remove from sidebar

**Files:**
- Modify: `lib/presentation/settings/settings_screen.dart`
- Modify: `lib/presentation/home/sidebar_drawer.dart`

**Interfaces:**
- Consumes: `profile` (the `UserModel?` already in scope inside the `StreamBuilder`'s `builder` from Task 1), specifically `profile?.isAdmin`.
- Produces: `_AdminSection` widget (no constructor params).

- [ ] **Step 1: Add the conditional Admin section to `settings_screen.dart`**

In the `children` list inside the `StreamBuilder`'s `builder`, change:

```dart
                      const SizedBox(height: 12),
                      _NotificationsSection(uid: uid),
                    ],
                  );
                },
              ),
```

to:

```dart
                      const SizedBox(height: 12),
                      _NotificationsSection(uid: uid),
                      if (profile?.isAdmin ?? false) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Admin',
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _AdminSection(),
                      ],
                    ],
                  );
                },
              ),
```

Then add this new widget class at the end of the file (after `_NotificationsSection`):

```dart
class _AdminSection extends StatelessWidget {
  const _AdminSection();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GlassContainer(
      padding: EdgeInsets.zero,
      // Transparent Material so the ListTile's ink splash paints above
      // GlassContainer's coloured box (otherwise it's hidden + asserts).
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          leading: Icon(Icons.admin_panel_settings_outlined, color: cs.tertiary),
          title: Text(
            'Admin Dashboard',
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'System analytics & security',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.pushNamed(context, '/admin-dashboard'),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run static analysis to verify Step 1 compiles clean**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Remove the Admin Dashboard item from `sidebar_drawer.dart`**

In `lib/presentation/home/sidebar_drawer.dart`, remove the now-unused import:

```dart
import '../../data/models/user_model.dart';
```

Then remove this block entirely (it sits between the "Key Vault" `_DrawerItem` and the "Settings" `_DrawerItem`):

```dart
            if (user != null)
              StreamBuilder<UserModel?>(
                stream: authRepo.streamUserProfile(user.uid),
                builder: (context, snapshot) {
                  final isAdmin = snapshot.data?.isAdmin ?? false;
                  if (!isAdmin) return const SizedBox.shrink();
                  
                  return _DrawerItem(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Admin Dashboard',
                    subtitle: 'System analytics & security',
                    color: Theme.of(context).colorScheme.tertiary,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/admin-dashboard');
                    },
                  );
                },
              ),

```

- [ ] **Step 4: Run static analysis to verify the sidebar still compiles clean**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: Manual verification**

Using an admin test account, run the app and open Settings. Confirm:
- An "Admin" section appears below "Notifications", with a single "Admin Dashboard" row; tapping it navigates to the existing Admin Dashboard.
- Open the sidebar drawer: confirm "Admin Dashboard" no longer appears there.
- Using a non-admin test account, confirm the "Admin" section does not appear in Settings at all (not even an empty header).

- [ ] **Step 6: Commit**

```bash
git add lib/presentation/settings/settings_screen.dart lib/presentation/home/sidebar_drawer.dart
git commit -m "feat(settings): add Admin Dashboard shortcut, remove from sidebar"
```

---

### Task 4: Rename sidebar "Find Friends" to "Connections"

**Files:**
- Modify: `lib/presentation/home/sidebar_drawer.dart`

**Interfaces:** None — label-only change, no new symbols.

- [ ] **Step 1: Rename the label**

In `lib/presentation/home/sidebar_drawer.dart`, change:

```dart
            _DrawerItem(
              icon: Icons.people_outline_rounded,
              label: 'Find Friends',
              onTap: () {
```

to:

```dart
            _DrawerItem(
              icon: Icons.people_outline_rounded,
              label: 'Connections',
              onTap: () {
```

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Run the full security test suite as a final regression check**

Run: `flutter test test/security/ --reporter=expanded`
Expected: `All tests passed!` (33/33, unchanged from before this plan — none of these tests touch Settings or the sidebar)

- [ ] **Step 4: Final manual verification**

Run the app. Confirm the sidebar drawer now shows "Connections" (not "Find Friends") and still navigates to the same Find Friends screen as before. Confirm the full Settings screen end-to-end: General → Account → Notifications → (Admin, if admin) all appear in that order and all function as verified in Tasks 1-3.

- [ ] **Step 5: Commit**

```bash
git add lib/presentation/home/sidebar_drawer.dart
git commit -m "refactor(sidebar): rename Find Friends to Connections"
```
