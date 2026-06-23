import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../agent/agent_provider.dart';
import '../agent/action_router.dart';      

/// AgentOverlayWrapper — The persistent Vision agent UI overlay.
/// 
/// This wraps the entire app and provides:
/// 1. A floating orb that shows agent state (resting/listening/thinking/etc.)
/// 2. A transcript bar showing what the user said
/// 3. An expandable status card with waveform/spinner animations
/// 4. Manual activation via long-press on the orb
class AgentOverlayWrapper extends StatefulWidget {
  final Widget child;

  const AgentOverlayWrapper({super.key, required this.child});

  @override
  State<AgentOverlayWrapper> createState() => _AgentOverlayWrapperState();
}

class _AgentOverlayWrapperState extends State<AgentOverlayWrapper>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _orbGlowController;

  @override
  void initState() {
    super.initState();

    // Pulse animation for the orb
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Wave animation for audio visualizer
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Glow animation for active states
    _orbGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Listen for intent execution
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final agent = Provider.of<AgentProvider>(context, listen: false);
      agent.addListener(_onAgentUpdate);
    });
  }

  void _onAgentUpdate() {
    if (!mounted) return;
    final agent = Provider.of<AgentProvider>(context, listen: false);

    // Execute pending intents
    final intent = agent.consumeLastIntent;
    if (intent != null) {
      ActionRouter.executeAction(context, intent);
    }

    // Manage animations based on state
    _updateAnimations(agent.state);
  }

  void _updateAnimations(AgentState state) {
    switch (state) {
      case AgentState.listening:
        _pulseController.repeat(reverse: true);
        _waveController.repeat(reverse: true);
        _orbGlowController.repeat(reverse: true);
        break;
      case AgentState.thinking:
        _pulseController.repeat(reverse: true);
        _waveController.stop();
        _orbGlowController.repeat(reverse: true);
        break;
      case AgentState.speaking:
        _pulseController.stop();
        _waveController.repeat(reverse: true);
        _orbGlowController.forward();
        break;
      case AgentState.waking:
        _pulseController.forward();
        _orbGlowController.forward();
        break;
      default:
        _pulseController.stop();
        _waveController.stop();
        _orbGlowController.stop();
        _pulseController.reset();
        _waveController.reset();
        _orbGlowController.reset();
    }
  }

  @override
  void dispose() {
    try {
      final agent = Provider.of<AgentProvider>(context, listen: false);
      agent.removeListener(_onAgentUpdate);
    } catch (e) {
      debugPrint('[AgentOverlay] Error removing listener in dispose: $e');
    }
    _pulseController.dispose();
    _waveController.dispose();
    _orbGlowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // The actual app content — wrapped with double-tap detection
          // Double-tap ANYWHERE to activate Vision (critical for blind users)
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTap: () {
              final agent = Provider.of<AgentProvider>(context, listen: false);
              if (agent.agentEnabled && !agent.isActive) {
                agent.startListening();
              }
            },
            child: widget.child,
          ),

          // Agent overlay
          Consumer<AgentProvider>(
            builder: (context, agent, child) {
              if (!agent.agentEnabled) return const SizedBox.shrink();

              return Stack(
                children: [
                  // Transcript bar (shows what user said)
                  if (agent.lastUserTranscript.isNotEmpty && agent.isActive)
                    _buildTranscriptBar(agent),

                  // Status card (expanded view when active)
                  if (agent.isActive)
                    _buildStatusCard(agent),

                  // Floating orb (only visible when active as requested)
                  if (agent.isActive)
                    _buildFloatingOrb(agent),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  FLOATING ORB — The main interaction point
  // ═══════════════════════════════════════════
  Widget _buildFloatingOrb(AgentProvider agent) {
    final Color orbColor = _getStateColor(agent.state);
    final bool isActive = agent.isActive;
    final double orbSize = isActive ? 64.0 : 52.0;

    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 24,
      right: 20,
      child: GestureDetector(
        onTap: () {
          if (!agent.isActive) {
            agent.startListening();
          } else {
            agent.stopListening();
          }
        },
        onLongPress: () {
          // Long press to manually activate
          agent.startListening();
        },
        child: AnimatedBuilder(
          animation: _orbGlowController,
          builder: (context, child) {
            final glowIntensity = isActive ? _orbGlowController.value * 0.6 + 0.2 : 0.0;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: orbSize,
              height: orbSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    orbColor.withOpacity(0.9),
                    orbColor.withOpacity(0.6),
                  ],
                ),
                boxShadow: [
                  // Base shadow
                  BoxShadow(
                    color: orbColor.withOpacity(0.3),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                  // Glow effect when active
                  if (isActive)
                    BoxShadow(
                      color: orbColor.withOpacity(glowIntensity),
                      blurRadius: 30,
                      spreadRadius: 8,
                    ),
                ],
              ),
              child: Center(
                child: _buildOrbIcon(agent),
              ),
            );
          },
        ),
      ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.5, 0.5)),
    );
  }

  Widget _buildOrbIcon(AgentProvider agent) {
    switch (agent.state) {
      case AgentState.listening:
        return _buildMiniWaveform();
      case AgentState.thinking:
        return const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white,
          ),
        );
      case AgentState.speaking:
        return _buildSpeakingIcon();
      case AgentState.waking:
        return const Icon(Icons.emoji_emotions_rounded, color: Colors.white, size: 26);
      case AgentState.executing:
        return const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 24);
      case AgentState.error:
        return const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24);
      default:
        return const Icon(Icons.mic_none_rounded, color: Colors.white70, size: 24);
    }
  }

  // ═══════════════════════════════════════════
  //  STATUS CARD — Expanded info when active
  // ═══════════════════════════════════════════
  Widget _buildStatusCard(AgentProvider agent) {
    final Color accentColor = _getStateColor(agent.state);

    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 96,
      right: 16,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: accentColor.withOpacity(0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.2),
              blurRadius: 20,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // State indicator
            _buildStateIndicator(agent),
            const SizedBox(width: 12),
            // Status text
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent.currentStatusText,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  if (agent.state == AgentState.error && agent.errorMessage.isNotEmpty)
                    Text(
                      agent.errorMessage,
                      style: GoogleFonts.poppins(
                        color: Colors.redAccent.withOpacity(0.8),
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.3),
    );
  }

  Widget _buildStateIndicator(AgentProvider agent) {
    switch (agent.state) {
      case AgentState.listening:
        return _buildAudioVisualizer();
      case AgentState.thinking:
        return SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: _getStateColor(agent.state),
          ),
        );
      case AgentState.speaking:
        return _buildSpeakingBars();
      case AgentState.executing:
        return Icon(
          Icons.check_circle_outline_rounded,
          color: _getStateColor(agent.state),
          size: 18,
        );
      case AgentState.error:
        return const Icon(
          Icons.error_outline_rounded,
          color: Colors.redAccent,
          size: 18,
        );
      default:
        return Icon(
          Icons.auto_awesome,
          color: _getStateColor(agent.state),
          size: 18,
        );
    }
  }

  // ═══════════════════════════════════════════
  //  TRANSCRIPT BAR — Shows what user said
  // ═══════════════════════════════════════════
  Widget _buildTranscriptBar(AgentProvider agent) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 155,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.75),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.format_quote_rounded,
              color: Colors.cyan.withOpacity(0.7),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '"${agent.lastUserTranscript}"',
                style: GoogleFonts.poppins(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.2),
    );
  }

  // ═══════════════════════════════════════════
  //  ANIMATION WIDGETS
  // ═══════════════════════════════════════════
  Widget _buildAudioVisualizer() {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(4, (index) {
            final phase = (index * 0.25 + _waveController.value) * 2 * math.pi;
            final height = 6.0 + math.sin(phase).abs() * 10.0;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: height,
              decoration: BoxDecoration(
                color: Colors.cyan,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildMiniWaveform() {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final phase = (index * 0.2 + _waveController.value) * 2 * math.pi;
            final height = 6.0 + math.sin(phase).abs() * 14.0;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 3,
              height: height,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildSpeakingBars() {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (index * 0.33 + _waveController.value) * 2 * math.pi;
            final height = 4.0 + math.sin(phase).abs() * 8.0;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: height,
              decoration: BoxDecoration(
                color: const Color(0xFF00E676),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildSpeakingIcon() {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(4, (index) {
            final phase = (index * 0.25 + _waveController.value) * 2 * math.pi;
            final height = 4.0 + math.sin(phase).abs() * 12.0;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 2.5,
              height: height,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }

  // ═══════════════════════════════════════════
  //  STATE COLOR MAPPING
  // ═══════════════════════════════════════════
  Color _getStateColor(AgentState state) {
    return switch (state) {
      AgentState.resting   => const Color(0xFF546E7A),  // Cool grey
      AgentState.waking    => const Color(0xFF00BCD4),   // Cyan
      AgentState.listening => const Color(0xFF00BCD4),   // Cyan
      AgentState.thinking  => const Color(0xFFFF9800),   // Amber
      AgentState.speaking  => const Color(0xFF00E676),   // Green
      AgentState.executing => const Color(0xFF4A90D9),   // Blue
      AgentState.error     => const Color(0xFFEF5350),   // Red
      AgentState.disabled  => const Color(0xFF424242),   // Dark grey
    };
  }
}
