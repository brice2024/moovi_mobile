import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:moovi/driversScreens/wallet/driver_wallet_page.dart';
import 'package:moovi/services/driver_service.dart';
import 'package:moovi/userScreens/mapPage.dart';
import 'package:moovi/userScreens/payments/payments_page.dart';
import 'package:moovi/userScreens/profil/profile_page.dart';
import 'package:moovi/widgets/moovi_scaffold.dart';

import '../widgets/UserbottomNavBar.dart';
import 'history/history.dart';

class Pagesmanager extends StatefulWidget {
  const Pagesmanager({super.key});

  @override
  State<Pagesmanager> createState() => _PagesmanagerState();
}

class _PagesmanagerState extends State<Pagesmanager> {
  static const _tabCount = 4;
  static const _walletTab = 2;

  int _currentIndex = 0;

  /// Onglets déjà ouverts : on ne les construit qu'à la première visite,
  /// puis ils restent en mémoire (la carte garde son état).
  final Set<int> _visited = {0};

  /// null = vérification en cours.
  bool? _isDriver;

  @override
  void initState() {
    super.initState();
    _refreshDriverStatus();
  }

  Future<void> _refreshDriverStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _isDriver = false);
      return;
    }
    final isDriver = await DriverService.instance.isDriverRegistered(uid);
    if (mounted && isDriver != _isDriver) setState(() => _isDriver = isDriver);
  }

  void _select(int index) {
    if (index == _walletTab) _refreshDriverStatus();
    setState(() {
      _currentIndex = index;
      _visited.add(index);
    });
  }

  Widget _buildTab(int index) {
    if (!_visited.contains(index)) return const SizedBox.shrink();
    switch (index) {
      case 0:
        return MapPage(onProfileTap: () => _select(3));
      case 1:
        return const HistoryPage();
      case 2:
        if (_isDriver == null) {
          return const MooviGradientBackground(
            child: Center(child: CircularProgressIndicator(color: Colors.white)),
          );
        }
        return _isDriver!
            ? const DriverWalletPage(embedded: true)
            : const PaymentsPage();
      default:
        return ProfilePage(onBack: () => _select(0));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Le bouton retour Android ramène d'abord à l'onglet « COURSE ».
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            IndexedStack(
              index: _currentIndex,
              children: [for (var i = 0; i < _tabCount; i++) _buildTab(i)],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: CustomNavbar(
                selectedIndex: _currentIndex,
                onItemSelected: _select,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
