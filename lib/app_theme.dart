import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Theme Palette - Light (Elegant)
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Colors.white;
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightTextMain = Color(0xFF0F172A); // Black font
  static const Color lightTextSecondary = Color(0xFF64748B);

  // Theme Palette - Dark (Admin/Premium)
  static const Color darkBg = Color(0xFF0F172A);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkTextMain = Color(0xFFF8FAFC); // White font
  static const Color darkTextSecondary = Color(0xFF94A3B8);

  // Theme-unqualified aliases — resolve to dark palette (app default)
  static const Color textMain = darkTextMain;
  static const Color textSecondary = darkTextSecondary;

  static const Color primaryGold = Color(0xFFF59E0B);
  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color accentPurple = Color(0xFF8B5CF6);

  // Glass Effects
  static const double glassBlur = 16.0;
  static Color get glassBgLight => Colors.white.withValues(alpha: 0.6);
  static Color get glassBorderLight => Colors.white.withValues(alpha: 0.3);
  static Color get glassBgDark => Colors.white.withValues(alpha: 0.08);
  static Color get glassBorderDark => Colors.white.withValues(alpha: 0.15);

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: lightBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.light,
        surface: lightSurface,
        onSurface: lightTextMain,
        outline: lightBorder,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(
        base.textTheme.copyWith(
          bodyLarge: const TextStyle(color: lightTextMain),
          bodyMedium: const TextStyle(color: lightTextMain),
          titleLarge: GoogleFonts.poppins(
            color: lightTextMain,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: lightBg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.poppins(
          color: lightTextMain,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: darkBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryGold,
        brightness: Brightness.dark,
        surface: darkSurface,
        onSurface: darkTextMain,
        outline: darkBorder,
      ),
      textTheme: GoogleFonts.poppinsTextTheme(
        base.textTheme.copyWith(
          bodyLarge: const TextStyle(color: darkTextMain),
          bodyMedium: const TextStyle(color: darkTextMain),
          titleLarge: GoogleFonts.poppins(
            color: darkTextMain,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkBg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.poppins(
          color: darkTextMain,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
