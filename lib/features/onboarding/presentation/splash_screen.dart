import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'welcome_screen.dart';

/// Animated loading screen: the icon drops in from the top, the MOWR wordmark
/// bounces up from the bottom, and they settle together with a gap between —
/// then it hands off to the welcome screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const routePath = '/splash';

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<Offset> _iconSlide;
  late final Animation<double> _iconFade;
  late final Animation<Offset> _wordSlide;
  late final Animation<double> _wordFade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Icon: falls in from above and settles early.
    _iconSlide = Tween(begin: const Offset(0, -1.6), end: Offset.zero).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0, 0.55, curve: Curves.easeOutCubic)),
    );
    _iconFade = CurvedAnimation(parent: _c, curve: const Interval(0, 0.4));

    // Wordmark: springs up from below with a bounce, slightly after the icon.
    _wordSlide = Tween(begin: const Offset(0, 1.8), end: Offset.zero).animate(
      CurvedAnimation(parent: _c, curve: const Interval(0.4, 1, curve: Curves.elasticOut)),
    );
    _wordFade = CurvedAnimation(parent: _c, curve: const Interval(0.4, 0.7));

    _c.forward().whenComplete(() {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) context.go(WelcomeScreen.routePath);
      });
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // White ground so the icon's baked-in white background blends seamlessly
    // (the mark reads as ink on white, no visible box).
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FadeTransition(
              opacity: _iconFade,
              child: SlideTransition(
                position: _iconSlide,
                child: Image.asset(
                  'assets/brand/mowr_icon.png',
                  width: 116,
                  height: 116,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FadeTransition(
              opacity: _wordFade,
              child: SlideTransition(
                position: _wordSlide,
                child: Image.asset(
                  'assets/brand/mowr_wordmark.png',
                  height: 40,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
