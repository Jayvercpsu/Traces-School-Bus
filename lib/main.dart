import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/passenger/passenger_home_screen.dart';
import 'features/driver/driver_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const ProviderScope(child: TracesApp()));
}

class TracesApp extends StatelessWidget {
  const TracesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'T.R.AC.E.S.S',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/passenger': (context) => const PassengerHomeScreen(),
        '/driver': (context) => const DriverHomeScreen(),
      },
    );
  }
}