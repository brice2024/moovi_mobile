import 'dart:async';

import 'package:flutter/material.dart';
import 'package:moovi/authScreens/SignOrLogin.dart';
import 'package:moovi/userScreens/PagesManager.dart';
import 'services/session.dart';

/// Affiche l'accueil si une session API est active, sinon l'écran de connexion.
/// La session est restaurée dans `main()` avant le premier affichage.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late StreamSubscription<AppUser?> _sub;
  AppUser? _user = AppSession.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _sub = AppSession.instance.changes.listen((user) {
      if (!mounted) return;
      final loggedOut = _user != null && user == null;
      setState(() => _user = user);
      if (loggedOut) {
        // Ferme les écrans empilés (mode chauffeur, profil…) après déconnexion.
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _user != null ? const Pagesmanager() : const Signorlogin();
  }
}
