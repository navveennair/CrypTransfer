import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/utils/theme_service.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository.dart';
import '../auth/login_screen.dart';
import '../widgets/shared_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final authRepo = AuthRepository();
    final uid = authRepo.currentUid;
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Welcome banner ────────────────────────────────
            GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              color: cs.primary.withValues(alpha: 0.1),
              borderColor: cs.primary.withValues(alpha: 0.2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.settings_suggest_rounded, color: cs.primary, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preferences',
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          'Configure your secure environment.',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'General',
              style: tt.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            GlassContainer(
              padding: EdgeInsets.zero,
              // Transparent Material so the ListTile's ink splash paints above
              // GlassContainer's coloured box (otherwise it's hidden + asserts).
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: Icon(Icons.palette_outlined, color: cs.primary),
                  title: Text(
                    'Appearance',
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Theme and display options',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
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

class AppearanceSubScreen extends StatelessWidget {
  const AppearanceSubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final themeService = context.watch<ThemeService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Appearance', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 16, 12),
              child: Text(
                'Select Theme',
                style: tt.labelSmall?.copyWith(
                  color: cs.primary,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            GlassContainer(
              padding: EdgeInsets.zero,
              child: RadioGroup<ThemeMode>(
                groupValue: themeService.themeMode,
                onChanged: (mode) => themeService.setThemeMode(mode!),
                child: Column(
                  children: [
                    _ThemeOption(
                      value: ThemeMode.system,
                      label: 'System Default',
                      subtitle: 'Follows device setting',
                      icon: Icons.brightness_auto_outlined,
                      isFirst: true,
                    ),
                    const Divider(height: 1),
                    _ThemeOption(
                      value: ThemeMode.light,
                      label: 'Light',
                      subtitle: 'Elegant light mode (Default)',
                      icon: Icons.light_mode_outlined,
                    ),
                    const Divider(height: 1),
                    _ThemeOption(
                      value: ThemeMode.dark,
                      label: 'Dark',
                      subtitle: 'Premium dark mode',
                      icon: Icons.dark_mode_outlined,
                      isLast: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final ThemeMode value;
  final String label;
  final String subtitle;
  final IconData icon;
  final bool isFirst;
  final bool isLast;

  const _ThemeOption({
    required this.value,
    required this.label,
    required this.subtitle,
    required this.icon,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return RadioListTile<ThemeMode>(
      value: value,
      title: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Text(
            label,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 28),
        child: Text(
          subtitle,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(16) : Radius.zero,
          bottom: isLast ? const Radius.circular(16) : Radius.zero,
        ),
      ),
    );
  }
}

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
