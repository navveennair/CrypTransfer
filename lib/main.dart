import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app_theme.dart';
import 'firebase_options.dart';
import 'presentation/auth/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const CrypTransferApp());
}

class CrypTransferApp extends StatelessWidget {
  const CrypTransferApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CrypTransfer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const SplashScreen(),
    );
  }
}
