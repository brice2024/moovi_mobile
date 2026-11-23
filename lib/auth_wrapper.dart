import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:moovi/authScreens/SignOrLogin.dart';
import 'package:moovi/userScreens/PagesManager.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';


class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {

        // Chargement
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: MooviGradientBackground(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icon/MooviOrange.png',
                      width: 180,
                      color: Colors.white,
                      colorBlendMode: BlendMode.srcIn,
                    ),
                    const SizedBox(height: 32),
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Utilisateur connecté
        if (snapshot.hasData) {
          return const Pagesmanager();
        }

        // Utilisateur non connecté
        return const Signorlogin();
      },
    );
  }
}