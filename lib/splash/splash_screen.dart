import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth_wrapper.dart';
import '../theme/app_colors.dart';

/// Splash animé (maquettes 1 → 4) :
/// 1. petit symbole « oo » orange centré sur fond blanc ;
/// 2. le symbole grossit ;
/// 3. il reprend sa taille et glisse à gauche pendant que « MOOVI » apparaît ;
/// 4. transition vers un écran blanc, puis fondu vers l'[AuthWrapper].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _total = Duration(milliseconds: 2600);

  /// Taille du symbole « oo » au repos (maquette 1 : ~66 x 40 pt).
  static const double _markWidth = 66;

  late final AnimationController _controller;

  // Phase 2 : le symbole grossit (x2.25), puis revient à sa taille.
  late final Animation<double> _grow;
  late final Animation<double> _shrink;
  // Phase 3 : le logo « MOOVI » apparaît à droite du symbole.
  late final Animation<double> _wordReveal;
  // Phase 4 : tout s'efface vers le blanc.
  late final Animation<double> _fadeOut;

  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _total);

    _grow = Tween<double>(begin: 1, end: 2.25).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.15, 0.40, curve: Curves.easeOutBack),
    ));
    _shrink = Tween<double>(begin: 1, end: 1 / 2.25).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 0.62, curve: Curves.easeInOutCubic),
    ));
    _wordReveal = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.50, 0.70, curve: Curves.easeOutCubic),
    );
    _fadeOut = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.84, 1.0, curve: Curves.easeIn),
    );

    _controller.forward().whenComplete(_goNext);
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => const AuthWrapper(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final reveal = _wordReveal.value;
            const wordWidth = 170.0;
            const gap = 10.0;
            return Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Opacity(
                    opacity: 1 - _fadeOut.value,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: _grow.value * _shrink.value *
                              (1 + 0.1 * reveal),
                          child: const MooviMark(width: _markWidth),
                        ),
                        // Le mot « MOOVI » se déploie : sa largeur passe de 0 à
                        // [wordWidth], ce qui pousse le symbole vers la gauche.
                        ClipRect(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: reveal,
                            child: Opacity(
                              opacity: reveal,
                              child: Padding(
                                padding: const EdgeInsets.only(left: gap),
                                child: Image.asset(
                                  'assets/icon/MooviOrange.png',
                                  width: wordWidth,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Maquette 4 : léger voile gris en bas à gauche pendant la transition.
                if (_fadeOut.value > 0)
                  IgnorePointer(
                    child: Opacity(
                      opacity: _fadeOut.value,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.bottomLeft,
                            radius: 0.9,
                            colors: [Color(0xFFF2F2F2), Colors.white],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Symbole « oo » de Moovi : deux anneaux qui se chevauchent, dessinés en
/// Flutter (pas d'asset dédié). Les trous sont réellement transparents.
class MooviMark extends StatelessWidget {
  final double width;
  final Color color;

  const MooviMark({
    super.key,
    this.width = 66,
    this.color = AppColors.primary,
  });

  /// Rapport hauteur / largeur du symbole.
  static const double aspectRatio = 1.68;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width / aspectRatio,
      child: CustomPaint(painter: _MooviMarkPainter(color)),
    );
  }
}

class _MooviMarkPainter extends CustomPainter {
  final Color color;
  const _MooviMarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final holeR = r * 0.32;
    final cy = size.height / 2;
    final left = Offset(r, cy);
    final right = Offset(size.width - r, cy);

    final discs = Path()
      ..addOval(Rect.fromCircle(center: left, radius: r))
      ..addOval(Rect.fromCircle(center: right, radius: r));
    final holes = Path()
      ..addOval(Rect.fromCircle(center: left, radius: holeR))
      ..addOval(Rect.fromCircle(center: right, radius: holeR));

    final mark = Path.combine(PathOperation.difference, discs, holes);
    canvas.drawPath(mark, Paint()
      ..color = color
      ..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_MooviMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
