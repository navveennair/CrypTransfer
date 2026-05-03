import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/utils/theme_service.dart';
import '../widgets/shared_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Configure your secure environment.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
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
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),

            GlassContainer(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Icons.palette_outlined, color: cs.primary),
                title: Text('Appearance', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text('Theme and display options', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AppearanceSubScreen()),
                ),
              ),
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
    final themeService = context.watch<ThemeService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Appearance', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
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
    return RadioListTile<ThemeMode>(
      value: value,
      title: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 28),
        child: Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
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
