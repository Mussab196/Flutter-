import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/app_provider.dart';
import '../ui/responsive_utils.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _dotsController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();
    _navigateAfterDelay();
  }

  void _navigateAfterDelay() async {
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      final appProvider = Provider.of<AppProvider>(context, listen: false);
      // Check BOTH local prefs AND Firebase auth for most reliable state
      final firebaseUser = FirebaseAuth.instance.currentUser;
      final isAuthenticated = appProvider.isAuthenticated || firebaseUser != null;
      
      // Sync AppProvider if Firebase says authenticated but prefs don't
      if (firebaseUser != null && !appProvider.isAuthenticated) {
        await appProvider.setAuthenticated(true);
      }
      
      if (!mounted) return;
      final route = isAuthenticated ? '/home' : '/onboarding';
      context.go(route);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0A1628),
              Color(0xFF132D4E),
            ],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: child,
                ),
              );
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Logo
                Container(
                  width: Responsive.space(100),
                  height: Responsive.space(100),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF5BA3E0),
                        Color(0xFF3B7DD8),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4A90D9).withOpacity(0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.visibility_rounded,
                    color: Colors.white,
                    size: 44.icon,
                  ),
                ),

                SizedBox(height: Responsive.space(28)),

                // App name
                Text(
                  'Aura',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),

                SizedBox(height: Responsive.space(8)),

                // Tagline
                Text(
                  'AI-Powered Accessibility',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF7B9CC4),
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1,
                  ),
                ),

                const Spacer(flex: 2),

                // 3 Dots Loading Animation
                AnimatedBuilder(
                  animation: _dotsController,
                  builder: (context, child) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (index) {
                        final delay = index * 0.2;
                        final animValue =
                            (_dotsController.value - delay).clamp(0.0, 1.0);
                        final scale = animValue < 0.5
                            ? 1.0 + (animValue * 2 * 0.5)
                            : 1.5 - ((animValue - 0.5) * 2 * 0.5);
                        final opacity = animValue < 0.5
                            ? 0.4 + (animValue * 2 * 0.6)
                            : 1.0 - ((animValue - 0.5) * 2 * 0.6);

                        return Container(
                          margin: EdgeInsets.symmetric(
                              horizontal: Responsive.space(4)),
                          child: Transform.scale(
                            scale: scale,
                            child: Container(
                              width: Responsive.space(10),
                              height: Responsive.space(10),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(opacity),
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),

                SizedBox(height: Responsive.space(40)),

                // Version
                Text(
                  'Version 1.0.0',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11.sp,
                  ),
                ),

                SizedBox(height: MediaQuery.of(context).padding.bottom + 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
