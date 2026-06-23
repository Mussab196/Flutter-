import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/obstacle_provider.dart';
import '../agent/agent_provider.dart';
import '../main.dart'; // for rootNavigatorKey
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  final TextEditingController _locationNameController = TextEditingController();

  static const String modelPath = 'yolov8s_float32';
  bool _isModelLoaded = false;

  // Throttle YOLO detection on navigation screen to ~5fps (200ms)
  // Full framerate is unnecessary here — obstacle detection at 5fps is
  // more than sufficient for walking speed, and saves massive CPU/GPU
  DateTime _lastNavDetectionTime = DateTime.now();

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Start navigation sensors
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navProvider = Provider.of<NavigationProvider>(context, listen: false);
      navProvider.startNavigation();
      
      // Register screen with agent
      Provider.of<AgentProvider>(context, listen: false).updateCurrentScreen('/navigation', 'GPS Navigation');
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _locationNameController.dispose();
    
    // Stop background navigation sensors when leaving screen
    // Use rootNavigatorKey context since 'this' may already be unmounted
    try {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) {
        final navProvider = Provider.of<NavigationProvider>(ctx, listen: false);
        navProvider.stopSensors();
        
        // Reset the agent's current screen tracking
        final agent = Provider.of<AgentProvider>(ctx, listen: false);
        if (agent.currentScreenRoute == '/navigation') {
          agent.updateCurrentScreen('/home', 'Home');
        }
      }
    } catch (e) {
      debugPrint('[NavigationScreen] Error in dispose cleanup: $e');
    }
    
    super.dispose();
  }

  void _onDetection(List<dynamic> results) {
    // Throttle to 200ms (~5 FPS) — walking-speed obstacle detection
    // doesn't need 30fps, and this massively reduces CPU/GPU load
    final now = DateTime.now();
    if (now.difference(_lastNavDetectionTime).inMilliseconds < 200) {
      return;
    }
    _lastNavDetectionTime = now;

    if (!mounted) return;

    if (!_isModelLoaded) {
      setState(() => _isModelLoaded = true);
    }
    
    // Feed obstacle classification pipeline for Virtual White Cane
    final obstacleProvider = Provider.of<ObstacleProvider>(context, listen: false);
    final screenSize = MediaQuery.of(context).size;
    obstacleProvider.setScreenSize(screenSize.width, screenSize.height);
    obstacleProvider.processDetections(
      results.map((r) => {
        'label': r.className,
        'confidence': r.confidence,
        'boundingBox': r.boundingBox,
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final compassSize = (size.width * 0.48).clamp(160.0, 260.0);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Stack(
          children: [
            // YOLO is in the background, only rendering ONCE, not rebuilding
            Positioned.fill(
              child: Center(
                child: Opacity(
                  opacity: 0.15,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(1000),
                    child: SizedBox(
                      width: compassSize * 1.5,
                      height: compassSize * 1.5,
                      child: YOLOView(
                        modelPath: modelPath,
                        task: YOLOTask.detect,
                        onResult: _onDetection,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // UI Elements that rebuild
            Positioned.fill(
              child: Consumer2<NavigationProvider, ObstacleProvider>(
                builder: (context, nav, obstacle, _) {
                  final dangerColor = ObstacleProvider.getDangerColor(nav.currentDangerLevel);
                  
                  return Column(
                    children: [
                      _buildHeader(nav),
                      const SizedBox(height: 8),

                      // Obstacle Alert Banner
                      if (obstacle.currentDangerLevel.index >= DangerLevel.warning.index)
                        _buildObstacleBanner(obstacle, dangerColor),

                      // Navigation Instruction Card
                      if (nav.isNavigating)
                        _buildTurnByTurnCard(nav),

                      // Compass
                      Expanded(
                        child: Center(
                          child: GestureDetector(
                            onTap: () => nav.announceCurrentStatus(),
                            child: _buildSmartCompass(nav, compassSize, dangerColor),
                          ),
                        ),
                      ),

                      // Info Panel
                      _buildInfoPanel(nav),

                      // Bottom Actions
                      _buildBottomActions(nav),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════
  Widget _buildHeader(NavigationProvider nav) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Back button
          GestureDetector(
            onTap: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nav.isNavigating ? 'Smart Navigation' : 'Free Walk',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                if (nav.isNavigating && nav.destinationName != null)
                  Text(
                    '→ ${nav.destinationName}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.cyan.shade300,
                    ),
                  ),
              ],
            ),
          ),
          // GPS Status
          _buildStatusBadge(nav),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildStatusBadge(NavigationProvider nav) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: nav.locationAvailable
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: nav.locationAvailable
              ? Colors.green.withValues(alpha: 0.4)
              : Colors.orange.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: nav.locationAvailable ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            nav.locationAvailable ? 'GPS' : '...',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: nav.locationAvailable ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  OBSTACLE BANNER
  // ═══════════════════════════════════════════════
  Widget _buildObstacleBanner(ObstacleProvider obstacle, Color dangerColor) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: dangerColor.withValues(alpha: 0.08 + (_pulseController.value * 0.06)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: dangerColor.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                ObstacleProvider.getDangerIcon(obstacle.currentDangerLevel),
                color: dangerColor,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  obstacle.warningMessage,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dangerColor,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).animate().fadeIn().slideY(begin: -0.3);
  }

  // ═══════════════════════════════════════════════
  //  TURN-BY-TURN CARD
  // ═══════════════════════════════════════════════
  Widget _buildTurnByTurnCard(NavigationProvider nav) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1A2A3A),
            const Color(0xFF0F1A25),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          // Turn direction icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              nav.getTurnIcon(),
              color: Colors.cyan,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nav.nextInstruction,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatDistance(nav.totalDistanceRemaining)} total remaining',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.cyan.shade300,
                  ),
                ),
              ],
            ),
          ),
          // Cancel navigation button
          GestureDetector(
            onTap: () => nav.stopNavigation(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.close, color: Colors.red, size: 18),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideX(begin: -0.1);
  }

  // ═══════════════════════════════════════════════
  //  SMART COMPASS
  // ═══════════════════════════════════════════════
  Widget _buildSmartCompass(NavigationProvider nav, double compassSize, Color dangerColor) {
    return Container(
      width: compassSize,
      height: compassSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF111118),
        border: Border.all(
          color: nav.obstacleAlertActive
              ? dangerColor.withValues(alpha: 0.5)
              : Colors.grey.shade800,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: (nav.obstacleAlertActive ? dangerColor : Colors.cyan)
                .withValues(alpha: 0.12),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Rotating compass rose
          Transform.rotate(
            angle: -nav.heading * (math.pi / 180),
            child: CustomPaint(
              size: Size(compassSize, compassSize),
              painter: _SmartCompassPainter(
                dangerLevel: nav.currentDangerLevel,
                isNavigating: nav.isNavigating,
                bearingToTarget: nav.bearingToNextWaypoint,
              ),
            ),
          ),

          // Fixed north indicator
          Positioned(
            top: 4,
            child: Icon(
              Icons.navigation_rounded,
              color: nav.obstacleAlertActive ? dangerColor : Colors.cyan,
              size: 22,
            ),
          ),

          // Center info
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${nav.heading.toStringAsFixed(0)}°',
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                nav.currentDirection,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.cyan,
                ),
              ),
              if (nav.isNavigating)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatDistance(nav.distanceToNextWaypoint),
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      color: Colors.cyan.shade300,
                    ),
                  ),
                ),
            ],
          ),

          // Direction text at bottom
          Positioned(
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                nav.movementStatus,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate()
        .fadeIn(duration: 400.ms)
        .scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutCubic);
  }

  // ═══════════════════════════════════════════════
  //  INFO PANEL
  // ═══════════════════════════════════════════════
  Widget _buildInfoPanel(NavigationProvider nav) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111118),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade800.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          // Speed + Direction
          _buildInfoRow(
            icon: Icons.speed_rounded,
            iconColor: Colors.amber,
            title: 'Speed',
            value: nav.speed > 0.25
                ? '${(nav.speed * 3.6).toStringAsFixed(1)} km/h'
                : 'Stationary',
          ),
          Divider(color: Colors.grey.shade800, height: 1),
          // Coordinates
          _buildInfoRow(
            icon: Icons.pin_drop_rounded,
            iconColor: Colors.green,
            title: 'Position',
            value: nav.currentPosition != null
                ? '${nav.currentPosition!.latitude.toStringAsFixed(5)}, ${nav.currentPosition!.longitude.toStringAsFixed(5)}'
                : nav.locationStatus,
          ),
          if (nav.isNavigating) ...[
            Divider(color: Colors.grey.shade800, height: 1),
            _buildInfoRow(
              icon: Icons.flag_rounded,
              iconColor: Colors.cyan,
              title: 'Destination',
              value: '${nav.destinationName ?? "Unknown"} — ${_formatDistance(nav.totalDistanceRemaining)}',
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1);
  }

  Widget _buildInfoRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  BOTTOM ACTIONS
  // ═══════════════════════════════════════════════
  Widget _buildBottomActions(NavigationProvider nav) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 6, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Save Location
          _buildActionBtn(
            icon: Icons.bookmark_add_rounded,
            label: 'Save',
            color: Colors.green.shade700,
            onTap: () => _showSaveLocationDialog(nav),
          ),
          // Announce Status
          _buildActionBtn(
            icon: Icons.spatial_audio_off_rounded,
            label: 'Status',
            color: Colors.cyan.shade700,
            onTap: () => nav.announceCurrentStatus(),
          ),
          // Navigate to Saved
          _buildActionBtn(
            icon: Icons.directions_rounded,
            label: 'Go To',
            color: Colors.purple.shade700,
            onTap: () => _showNavigateDialog(nav),
          ),
          // Voice toggle
          _buildActionBtn(
            icon: nav.voiceEnabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            label: nav.voiceEnabled ? 'Voice' : 'Muted',
            color: nav.voiceEnabled
                ? Colors.blue.shade700
                : Colors.grey.shade700,
            onTap: () => nav.toggleVoice(),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2);
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.8),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 10,
              color: Colors.grey.shade400,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  DIALOGS
  // ═══════════════════════════════════════════════
  void _showSaveLocationDialog(NavigationProvider nav) {
    _locationNameController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Save Current Location',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: _locationNameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. Home, Office, Masjid...',
            hintStyle: TextStyle(color: Colors.grey.shade600),
            filled: true,
            fillColor: Colors.grey.shade900,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = _locationNameController.text.trim();
              if (name.isNotEmpty) {
                nav.saveCurrentLocation(name);
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showNavigateDialog(NavigationProvider nav) {
    final locations = nav.savedLocations;
    if (locations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No saved locations. Tap "Save" to save your current location first.',
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.grey.shade800,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Navigate To',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: locations.length,
            itemBuilder: (ctx, index) {
              final name = locations.keys.elementAt(index);
              return ListTile(
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.place_rounded, color: Colors.cyan, size: 20),
                ),
                title: Text(
                  name,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(ctx);
                  nav.navigateToSaved(name);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: Colors.grey.shade500)),
          ),
        ],
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 100) return '${meters.round()} m';
    if (meters < 1000) return '${(meters / 10).round() * 10} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}

// ═══════════════════════════════════════════════
//  SMART COMPASS PAINTER
// ═══════════════════════════════════════════════
class _SmartCompassPainter extends CustomPainter {
  final DangerLevel dangerLevel;
  final bool isNavigating;
  final double bearingToTarget;

  _SmartCompassPainter({
    required this.dangerLevel,
    required this.isNavigating,
    required this.bearingToTarget,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    // Inner ring
    final ringPaint = Paint()
      ..color = Colors.grey.shade800.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius * 0.6, ringPaint);

    // Crosshairs
    final crossPaint = Paint()
      ..color = Colors.grey.shade800
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx - radius + 35, center.dy),
      Offset(center.dx + radius - 35, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius + 35),
      Offset(center.dx, center.dy + radius - 35),
      crossPaint,
    );

    // Direction labels
    final tp = TextPainter(textDirection: TextDirection.ltr);

    // N (highlighted cyan)
    tp.text = TextSpan(
      text: 'N',
      style: GoogleFonts.poppins(
        fontSize: 15,
        color: Colors.cyan,
        fontWeight: FontWeight.w700,
      ),
    );
    tp.layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, 6));

    // S, E, W
    _drawLabel(canvas, tp, 'S', Colors.grey.shade600,
        Offset(center.dx, size.height - 22), 13);
    _drawLabel(canvas, tp, 'W', Colors.grey.shade600,
        Offset(6, center.dy), 13, alignY: true);
    _drawLabel(canvas, tp, 'E', Colors.grey.shade600,
        Offset(size.width - 18, center.dy), 13, alignY: true);

    // Tick marks
    final tickPaint = Paint()
      ..color = Colors.grey.shade700
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 360; i += 30) {
      if (i % 90 != 0) {
        final angle = i * math.pi / 180;
        final innerR = radius - 14;
        final outerR = radius - 5;
        canvas.drawLine(
          Offset(
            center.dx + innerR * math.cos(angle - math.pi / 2),
            center.dy + innerR * math.sin(angle - math.pi / 2),
          ),
          Offset(
            center.dx + outerR * math.cos(angle - math.pi / 2),
            center.dy + outerR * math.sin(angle - math.pi / 2),
          ),
          tickPaint,
        );
      }
    }

    // Destination indicator (arrow on compass edge)
    if (isNavigating) {
      final targetAngle = bearingToTarget * math.pi / 180 - math.pi / 2;
      final arrowR = radius - 8;
      final arrowPos = Offset(
        center.dx + arrowR * math.cos(targetAngle),
        center.dy + arrowR * math.sin(targetAngle),
      );
      final arrowPaint = Paint()
        ..color = Colors.cyan
        ..style = PaintingStyle.fill;
      canvas.drawCircle(arrowPos, 5, arrowPaint);
    }
  }

  void _drawLabel(Canvas canvas, TextPainter tp, String text, Color color,
      Offset offset, double fontSize,
      {bool alignY = false}) {
    tp.text = TextSpan(
      text: text,
      style: GoogleFonts.poppins(
        fontSize: fontSize,
        color: color,
        fontWeight: FontWeight.w500,
      ),
    );
    tp.layout();
    final dx = alignY ? offset.dx : offset.dx - tp.width / 2;
    final dy = alignY ? offset.dy - tp.height / 2 : offset.dy;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _SmartCompassPainter oldDelegate) {
    return oldDelegate.dangerLevel != dangerLevel ||
        oldDelegate.isNavigating != isNavigating ||
        oldDelegate.bearingToTarget != bearingToTarget;
  }
}
