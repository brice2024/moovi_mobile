import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:moovi/theme/app_theme.dart';
import 'auth_wrapper.dart';
import 'driversScreens/test/offers_page.dart';
import 'firebase_options.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widgets is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: AuthWrapper(),
    );
  }
}

