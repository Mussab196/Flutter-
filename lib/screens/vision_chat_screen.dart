import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';
import '../agent/agent_provider.dart';
import 'package:google_fonts/google_fonts.dart';

class VisionChatScreen extends StatefulWidget {
  const VisionChatScreen({super.key});

  @override
  State<VisionChatScreen> createState() => _VisionChatScreenState();
}

class _VisionChatScreenState extends State<VisionChatScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    // Configure pulsing animation
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Register screen with agent
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AgentProvider>(context, listen: false).updateCurrentScreen('/vision-chat', 'Vision Chat');
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTap(AgentProvider agent) {
    // Start listening (this will also stop TTS automatically inside AgentProvider)
    agent.startListening();
    // Announce for blind users
    SemanticsService.announce("Listening, please speak.", TextDirection.ltr);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // High contrast background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 30),
          tooltip: "Go Back",
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          "Chat with Aura",
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
      body: Consumer<AgentProvider>(
        builder: (context, agent, child) {
          // Adjust animation speed based on state
          if (agent.isListening) {
            _pulseController.duration = const Duration(milliseconds: 500);
            if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
          } else if (agent.isProcessing) {
            _pulseController.duration = const Duration(milliseconds: 200);
            if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
          } else if (agent.isSpeaking) {
            _pulseController.duration = const Duration(seconds: 1);
            if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
          } else {
            _pulseController.duration = const Duration(seconds: 3);
            if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
          }

          // Determine UI color based on state
          Color glowColor = Colors.blueAccent;
          if (agent.isListening) glowColor = Colors.greenAccent;
          if (agent.isProcessing) glowColor = Colors.amberAccent;
          if (agent.isSpeaking) glowColor = Colors.purpleAccent;
          if (agent.state == AgentState.error) glowColor = Colors.redAccent;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleTap(agent),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Transcript Display Area (Useful for low-vision)
                    Expanded(
                      flex: 2,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (agent.lastUserTranscript.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '"${agent.lastUserTranscript}"',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 22,
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          Text(
                            agent.currentStatusText,
                            style: TextStyle(
                              color: glowColor,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                            textAlign: TextAlign.center,
                            semanticsLabel: "Status: ${agent.currentStatusText}",
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 60),
                    
                    // Huge Central Orb / Button
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _pulseAnimation.value,
                              child: Container(
                                width: 180,
                                height: 180,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: glowColor.withOpacity(0.2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: glowColor.withOpacity(0.6),
                                      blurRadius: 40,
                                      spreadRadius: 10,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _getIconForState(agent.state),
                                  size: 80,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Helpful instruction text
                    Expanded(
                      flex: 1,
                      child: Center(
                        child: Text(
                          "Tap anywhere to talk",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 20,
                            fontWeight: FontWeight.w500,
                          ),
                          semanticsLabel: "Double tap anywhere on the screen to talk to Aura.",
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _getIconForState(AgentState state) {
    switch (state) {
      case AgentState.listening:
        return Icons.mic;
      case AgentState.thinking:
        return Icons.memory;
      case AgentState.speaking:
        return Icons.volume_up;
      case AgentState.error:
        return Icons.error_outline;
      default:
        return Icons.graphic_eq;
    }
  }
}
