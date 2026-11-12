import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:moovi/theme/app_theme.dart';
import 'auth_wrapper.dart';
import 'driversScreens/test/offers_page.dart';
import 'firebase_options.dart';
import 'services/pawapay_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Initialisation PawaPay avec le token officiel Sandbox
  PawaPayService.instance.configure(
    apiToken: const String.fromEnvironment(
      'PAWAPAY_TOKEN',
      defaultValue:
          'eyJraWQiOiIxIiwiYWxnIjoiRVMyNTYifQ.eyJ0dCI6IkFBVCIsInN1YiI6IjQ0MDkiLCJtYXYiOiIxIiwiZXhwIjoyMTEwMDk3NTYyLCJpYXQiOjE3OTQ0NzgzNjIsInBtIjoiREFGLFBBRiIsImp0aSI6ImM5ZmU1NGMzLTkzM2MtNGU2Yi04MjEzLWQwZDExM2Q0NTBjNyJ9.C4B47fkFvu2ClcUavmws9kbwpu1fm9xnAIvGmVucNATY5ATStxVFFNj4aqLtX7xr9vMz9J4qO0feCMFiPZRMYw',
    ),
    production: true,
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

