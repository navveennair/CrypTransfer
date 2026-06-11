import 'package:flutter/material.dart';

import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../auth/login_screen.dart';
import '../settings/settings_screen.dart';
import '../vault/rsa_key_manager_screen.dart';
import '../widgets/shared_widgets.dart';
import 'find_friends_screen.dart';

class SidebarDrawer extends StatelessWidget {
  const SidebarDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final authRepo = AuthRepository();
    final user = authRepo.currentUser;
    final username = authRepo.currentDisplayName ?? 'User';
    final email = user?.email ?? '';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      width: MediaQuery.of(context).size.width * 0.8,
      child: GlassContainer(
        borderRadius: 0,
        blur: 30,
        color: cs.surface.withValues(alpha: isDark ? 0.90 : 0.95),
        borderColor: cs.outlineVariant.withValues(alpha: isDark ? 0.10 : 0.80),
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────
            Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 20,
                bottom: 24,
                left: 24,
                right: 24,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GlassContainer(
                    padding: const EdgeInsets.all(4),
                    borderRadius: 100,
                    color: cs.primary.withValues(alpha: 0.1),
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: cs.primary.withValues(alpha: 0.2),
                      child: Text(
                        username.isNotEmpty ? username[0].toUpperCase() : '?',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          email,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, indent: 24, endIndent: 24),
            const SizedBox(height: 16),

            // ── Navigation items ──────────────────────────────────
            _DrawerItem(
              icon: Icons.people_outline_rounded,
              label: 'Find Friends',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FindFriendsScreen()),
                );
              },
            ),

            _DrawerItem(
              icon: Icons.vpn_key_outlined,
              label: 'Key Vault',
              subtitle: 'Manage RSA encryption keys',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RsaKeyManagerScreen()),
                );
              },
            ),

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

            _DrawerItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),

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
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final itemColor = color ?? cs.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: itemColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: itemColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
