import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // GitHub Dark Palette constants
  static const Color githubDarkBg = Color(0xFF0D1117);
  static const Color githubDarkSurface = Color(0xFF161B22);
  static const Color githubDarkBorder = Color(0xFF30363D);
  static const Color githubDarkPrimary = Color(0xFF58A6FF);
  static const Color githubDarkText = Color(0xFFC9D1D9);
  static const Color githubDarkSecondaryText = Color(0xFF8B949E);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: githubDarkPrimary,
        brightness: Brightness.light,
      ),
      textTheme: GoogleFonts.interTextTheme(),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
      ),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: githubDarkBg,
      colorScheme: const ColorScheme.dark(
        primary: githubDarkPrimary,
        surface: githubDarkSurface,
        onSurface: githubDarkText,
        onSurfaceVariant: githubDarkSecondaryText,
        outline: githubDarkBorder,
        outlineVariant: Color(0xFF21262D),
        surfaceContainerLow: Color(0xFF0D1117),
        surfaceContainer: Color(0xFF161B22),
        surfaceContainerHigh: Color(0xFF21262D),
      ),
      cardTheme: CardThemeData(
        color: githubDarkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: githubDarkBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: githubDarkBg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: githubDarkText),
        titleTextStyle: TextStyle(
          color: githubDarkText,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: GoogleFonts.interTextTheme(
        const TextTheme(
          bodyLarge: TextStyle(color: githubDarkText),
          bodyMedium: TextStyle(color: githubDarkText),
          titleLarge: TextStyle(color: githubDarkText, fontWeight: FontWeight.bold),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: githubDarkBorder,
        thickness: 1,
      ),
    );
  }
}
