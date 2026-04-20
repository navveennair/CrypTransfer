import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/utils/theme_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Settings', style: GoogleFonts.inter())),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.palette_outlined, color: cs.primary),
            title: Text('Appearance', style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
            subtitle: Text('Theme and display options', style: GoogleFonts.inter(fontSize: 13)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AppearanceSubScreen()),
            ),
          ),
        ],
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
      appBar: AppBar(title: Text('Appearance', style: GoogleFonts.inter())),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Theme',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.primary,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outline),
            ),
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
                  Divider(height: 1, color: cs.outline),
                  _ThemeOption(
                    value: ThemeMode.light,
                    label: 'Light',
                    subtitle: 'Always light',
                    icon: Icons.light_mode_outlined,
                  ),
                  Divider(height: 1, color: cs.outline),
                  _ThemeOption(
                    value: ThemeMode.dark,
                    label: 'Dark',
                    subtitle: 'GitHub dark (#0d1117)',
                    icon: Icons.dark_mode_outlined,
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
        ],
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
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 28),
        child: Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: cs.onSurfaceVariant)),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(12) : Radius.zero,
          bottom: isLast ? const Radius.circular(12) : Radius.zero,
        ),
      ),
    );
  }
}
