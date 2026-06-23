import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../agent/agent_provider.dart';
import '../ui/responsive_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool voiceGuidanceEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AgentProvider>(context, listen: false)
          .updateCurrentScreen('/home', 'Home');
    });
  }

  List<Map<String, dynamic>> get menuItems => [
        {
          'icon': Icons.remove_red_eye_rounded,
          'title': 'Live Vision',
          'subtitle': 'Describe surroundings',
          'route': '/live-vision',
          'color': const Color(0xFF4A90D9),
        },
        {
          'icon': Icons.auto_stories_rounded,
          'title': 'Read Text',
          'subtitle': 'OCR & text to speech',
          'route': '/ocr-reader',
          'color': const Color(0xFF6C5CE7),
        },
        {
          'icon': Icons.face_retouching_natural_rounded,
          'title': 'Recognize People',
          'subtitle': 'Identify saved faces',
          'route': '/face-recognition',
          'color': const Color(0xFF00B894),
        },
        {
          'icon': Icons.explore_rounded,
          'title': 'Smart Navigation',
          'subtitle': 'GPS + Obstacle Detection',
          'route': '/navigation',
          'color': const Color(0xFFFFAB00),
        },
        {
          'icon': Icons.graphic_eq_rounded,
          'title': 'Chat with Aura',
          'subtitle': 'Voice AI Assistant',
          'route': '/vision-chat',
          'color': const Color(0xFF9B59B6),
        },
        {
          'icon': Icons.sos_rounded,
          'title': 'Emergency SOS',
          'subtitle': 'Quick help access',
          'route': '/sos',
          'color': const Color(0xFFE74C3C),
        },
        {
          'icon': Icons.settings_rounded,
          'title': 'Settings',
          'subtitle': 'Preferences & help',
          'route': '/settings',
          'color': const Color(0xFF636E72),
        },
      ];

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context);
    final userName = authProvider.userName;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF5F7FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: Responsive.space(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: Responsive.space(20)),

              // Header
              Text(
                'Welcome back',
                style: GoogleFonts.poppins(
                  fontSize: 14.sp,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
              Text(
                userName,
                style: GoogleFonts.poppins(
                  fontSize: 26.sp,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),

              SizedBox(height: Responsive.space(8)),

              // Subtitle
              Text(
                'How can I assist you today?',
                style: GoogleFonts.poppins(
                  fontSize: 14.sp,
                  color: const Color(0xFF4A90D9),
                  fontWeight: FontWeight.w500,
                ),
              ),

              SizedBox(height: Responsive.space(24)),

              // Menu Cards
              ...menuItems.map((item) => _buildMenuCard(
                    icon: item['icon'] as IconData,
                    title: item['title'] as String,
                    subtitle: item['subtitle'] as String,
                    route: item['route'] as String,
                    color: item['color'] as Color,
                    isDark: isDark,
                  )),

              // Voice Guidance Card
              _buildVoiceGuidanceCard(isDark),

              SizedBox(height: Responsive.space(24)),

              // Bottom Stats Section
              Container(
                padding: EdgeInsets.symmetric(
                    vertical: Responsive.space(18),
                    horizontal: Responsive.space(16)),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.grey.shade900.withOpacity(0.5)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(Responsive.radius(20)),
                  border: Border.all(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatItem(Icons.document_scanner_rounded, '24',
                        'Scans\nToday', const Color(0xFF4A90D9)),
                    _buildStatDivider(),
                    _buildStatItem(Icons.face_rounded, '12', 'Faces\nSaved',
                        const Color(0xFF6C5CE7)),
                    _buildStatDivider(),
                    _buildStatItem(Icons.route_rounded, '8', 'Routes',
                        const Color(0xFFFFAB00)),
                  ],
                ),
              ),

              SizedBox(height: Responsive.space(24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String route,
    required Color color,
    required bool isDark,
  }) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => context.push(route),
      child: Container(
        margin: EdgeInsets.only(bottom: Responsive.space(12)),
        padding: EdgeInsets.all(Responsive.space(14)),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade900.withOpacity(0.6) : Colors.white,
          borderRadius: BorderRadius.circular(Responsive.radius(16)),
          border: Border.all(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            // Icon Container
            Container(
              width: Responsive.space(46),
              height: Responsive.space(46),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(Responsive.radius(14)),
              ),
              child: Icon(
                icon,
                color: color,
                size: 22.icon,
              ),
            ),
            SizedBox(width: Responsive.space(14)),
            // Text Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 11.sp,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            // Arrow
            Icon(
              Icons.chevron_right_rounded,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
              size: 22.icon,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceGuidanceCard(bool isDark) {
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.only(bottom: Responsive.space(12)),
      padding: EdgeInsets.all(Responsive.space(14)),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900.withOpacity(0.6) : Colors.white,
        borderRadius: BorderRadius.circular(Responsive.radius(16)),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          // Icon Container
          Container(
            width: Responsive.space(46),
            height: Responsive.space(46),
            decoration: BoxDecoration(
              color: const Color(0xFF4A90D9).withOpacity(0.15),
              borderRadius: BorderRadius.circular(Responsive.radius(14)),
            ),
            child: Icon(
              voiceGuidanceEnabled
                  ? Icons.graphic_eq_rounded
                  : Icons.volume_off_rounded,
              color: const Color(0xFF4A90D9),
              size: 22.icon,
            ),
          ),
          SizedBox(width: Responsive.space(14)),
          // Text Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice Guidance',
                  style: GoogleFonts.poppins(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  voiceGuidanceEnabled
                      ? 'Active and listening'
                      : 'Tap to enable',
                  style: GoogleFonts.poppins(
                    fontSize: 11.sp,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
          // Toggle Switch
          Transform.scale(
            scale: Responsive.isSmall ? 0.85 : 1.0,
            child: Switch(
              value: voiceGuidanceEnabled,
              onChanged: (value) {
                setState(() {
                  voiceGuidanceEnabled = value;
                });
              },
              activeColor: const Color(0xFF4A90D9),
              activeTrackColor: const Color(0xFF4A90D9).withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      IconData icon, String value, String label, Color color) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: Responsive.space(42),
          height: Responsive.space(42),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(Responsive.radius(12)),
          ),
          child: Icon(
            icon,
            color: color,
            size: 20.icon,
          ),
        ),
        SizedBox(height: Responsive.space(8)),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 18.sp,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 9.sp,
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStatDivider() {
    final theme = Theme.of(context);
    return Container(
      height: Responsive.space(50),
      width: 1,
      color: theme.colorScheme.onSurface.withOpacity(0.1),
    );
  }
}
