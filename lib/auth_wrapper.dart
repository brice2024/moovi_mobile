import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:moovi/authScreens/SignOrLogin.dart';
import 'package:moovi/userScreens/PagesManager.dart';
import 'package:moovi/userScreens/mapPage.dart';


class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {

        // Chargement
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
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