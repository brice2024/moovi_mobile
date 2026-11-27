import 'package:flutter/material.dart';
import 'package:moovi/theme/app_theme.dart';
import 'auth_wrapper.dart';
import 'services/Auth.dart';
import 'services/local_notifications.dart';
import 'services/messaging_service.dart';
import 'services/realtime_service.dart';
import 'widgets/in_app_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restaure la session JWT enregistrée (remplace la persistance Firebase Auth).
  await AuthService.instance.restoreSession();
  // Connexion Socket.IO à l'API (ouverte/fermée selon la session).
  RealtimeService.instance.init();
  MessagingService.instance.init();
  InAppNotifications.instance.init();
  await LocalNotifications.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widgets is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moovi',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: InAppNotifications.instance.messengerKey,
      navigatorKey: InAppNotifications.instance.navigatorKey,
      theme: AppTheme.lightTheme,
      home: const AuthWrapper(),
    );
  }
}
