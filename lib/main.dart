import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app_theme.dart';
import 'core/utils/kill_switch_outbox.dart';
import 'firebase_options.dart';
import 'presentation/auth/splash_screen.dart';
import 'services/firestore_migration.dart';
import 'presentation/admin/admin_dashboard.dart';
import 'presentation/admin/admin_guard.dart';
import 'package:provider/provider.dart';
import 'core/utils/theme_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirestoreMigration.initializeCollections();
  await KillSwitchOutbox.resumeIfPending();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeService(),
      child: const CrypTransferApp(),
    ),
  );
}

class CrypTransferApp extends StatelessWidget {
  const CrypTransferApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    return MaterialApp(
      title: 'CrypTransfer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeService.themeMode,
      home: const SplashScreen(),
      routes: {
        '/admin-dashboard': (context) => AdminGuard(child: const AdminDashboard()),
      },
    );
  }
}
