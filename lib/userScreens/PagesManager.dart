import 'package:flutter/material.dart';
import 'package:moovi/userScreens/mapPage.dart';
import 'package:moovi/userScreens/profil/profile_page.dart';

import '../widgets/UserbottomNavBar.dart';
import 'history/history.dart';

class Pagesmanager extends StatefulWidget {
  const Pagesmanager({super.key});

  @override
  State<Pagesmanager> createState() => _PagesmanagerState();
}

class _PagesmanagerState extends State<Pagesmanager> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // IndexedStack : la carte (et la course en cours, son paiement…)
          // reste vivante quand on consulte l'historique ou le profil.
          IndexedStack(
            index: _currentIndex,
            children: const [MapPage(), HistoryPage(), ProfilePage()],
          ),

          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20,
            left: 10,
            right: 10,
            child: CustomNavbar(
              selectedIndex: _currentIndex,
              onItemSelected: (i) => setState(() => _currentIndex = i),
            ),
          ),
        ],
      ),
    );
  }
}
