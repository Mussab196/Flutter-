import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../ui/responsive_utils.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _slides = [
    {
      'icon': Icons.remove_red_eye_rounded,
      'title': 'See the World Differently',
      'subtitle':
          'AI describes your surroundings in real-time with advanced computer vision',
      'color': const Color(0xFF4A90D9),
    },
    {
      'icon': Icons.auto_stories_rounded,
      'title': 'Read Any Text Instantly',
      'subtitle':
          'Point your camera at any text and hear it read aloud clearly',
      'color': const Color(0xFF6C5CE7),
    },
    {
      'icon': Icons.people_alt_rounded,
      'title': 'Recognize Familiar Faces',
      'subtitle':
          'Save faces of friends and family to get notified when they are nearby',
      'color': const Color(0xFF00B894),
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
  }

  void _nextPage() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      context.go('/login');
    }
  }

  void _skip() {
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final currentSlide = _slides[_currentPage];
    final currentColor = currentSlide['color'] as Color;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header with Skip
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: Responsive.space(20),
                  vertical: Responsive.space(12)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Skip button
                  TextButton(
                    onPressed: _skip,
                    child: Text(
                      'Skip',
                      style: GoogleFonts.poppins(
                        fontSize: 13.sp,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: _slides.length,
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  final color = slide['color'] as Color;

                  return Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: Responsive.space(32)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon
                        Container(
                          width:
                              size.width * (Responsive.isSmall ? 0.32 : 0.35),
                          height:
                              size.width * (Responsive.isSmall ? 0.32 : 0.35),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color.withOpacity(0.1),
                          ),
                          child: Icon(
                            slide['icon'] as IconData,
                            color: color,
                            size:
                                size.width * (Responsive.isSmall ? 0.13 : 0.15),
                          ),
                        ),

                        SizedBox(height: size.height * 0.04),

                        // Title
                        Text(
                          slide['title'] as String,
                          style: GoogleFonts.poppins(
                            fontSize: 24.sp,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1A1A2E),
                            height: 1.3,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        SizedBox(height: Responsive.space(14)),

                        // Subtitle
                        Text(
                          slide['subtitle'] as String,
                          style: GoogleFonts.poppins(
                            fontSize: 14.sp,
                            color: Colors.grey.shade600,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Bottom section
            Padding(
              padding: EdgeInsets.fromLTRB(
                  Responsive.space(32),
                  Responsive.space(16),
                  Responsive.space(32),
                  MediaQuery.of(context).padding.bottom + 24),
              child: Column(
                children: [
                  // Page indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: EdgeInsets.symmetric(
                            horizontal: Responsive.space(4)),
                        height: Responsive.space(8),
                        width: _currentPage == index
                            ? Responsive.space(24)
                            : Responsive.space(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: _currentPage == index
                              ? currentColor
                              : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: Responsive.space(28)),

                  // Next/Get Started button
                  SizedBox(
                    width: double.infinity,
                    height: Responsive.space(50),
                    child: ElevatedButton(
                      onPressed: _nextPage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: currentColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(Responsive.radius(16)),
                        ),
                      ),
                      child: Text(
                        _currentPage == _slides.length - 1
                            ? 'Get Started'
                            : 'Continue',
                        style: GoogleFonts.poppins(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
