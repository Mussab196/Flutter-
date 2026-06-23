import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import '../ui/responsive_utils.dart';
import '../agent/agent_provider.dart';

class FaceAuthScreen extends StatefulWidget {
  final bool isLogin;

  const FaceAuthScreen({super.key, required this.isLogin});

  @override
  State<FaceAuthScreen> createState() => _FaceAuthScreenState();
}

class _FaceAuthScreenState extends State<FaceAuthScreen> {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isProcessing = false;
  CameraLensDirection _currentLensDirection = CameraLensDirection.front;
  List<CameraDescription> _cameras = [];
  String _statusMessage = "Position your face in the circle";
  final TextEditingController _nameController = TextEditingController();

  // API URL will be fetched from AgentProvider or default to localhost
  String get apiUrl {
    final agent = Provider.of<AgentProvider>(context, listen: false);
    if (agent.backendUrl.isNotEmpty) return agent.backendUrl;
    return Platform.isAndroid ? 'http://10.0.2.2:8000' : 'http://127.0.0.1:8000';
  }

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      await _setCamera(_currentLensDirection);
    } catch (e) {
      debugPrint('Camera init error: $e');
      setState(() {
        _statusMessage = "Camera Error. Please restart.";
      });
    }
  }

  Future<void> _setCamera(CameraLensDirection direction) async {
    if (_cameras.isEmpty) return;

    final targetCamera = _cameras.firstWhere(
      (c) => c.lensDirection == direction,
      orElse: () => _cameras.first,
    );

    if (_cameraController != null) {
      await _cameraController!.dispose();
    }

    _cameraController = CameraController(
      targetCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    if (!mounted) return;
    setState(() => _isCameraReady = true);
  }

  void _toggleCamera() {
    if (_isProcessing) return;
    setState(() {
      _isCameraReady = false;
      _currentLensDirection = _currentLensDirection == CameraLensDirection.front
          ? CameraLensDirection.back
          : CameraLensDirection.front;
    });
    _setCamera(_currentLensDirection);
  }

  Future<void> _captureAndAuthenticate() async {
    if (!_isCameraReady || _cameraController == null || _isProcessing) return;

    if (!widget.isLogin && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your name first!")),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = "Analyzing face structure...";
    });

    try {
      HapticFeedback.mediumImpact();
      final XFile image = await _cameraController!.takePicture();

      if (widget.isLogin) {
        await _handleLogin(image);
      } else {
        await _handleSignup(image);
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Error capturing face. Try again.";
        _isProcessing = false;
      });
    }
  }

  Future<void> _handleLogin(XFile image) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$apiUrl/verify_face'));
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var json = jsonDecode(responseData);

      if (response.statusCode == 200 && json['token'] != null) {
        setState(() => _statusMessage = "Face Matched! Logging in...");
        
        // Login to Firebase with Custom Token from Python
        await FirebaseAuth.instance.signInWithCustomToken(json['token']);
        
        if (mounted) {
          HapticFeedback.heavyImpact();
          context.go('/home');
        }
      } else {
        setState(() {
          _statusMessage = "Face not recognized. Try again.";
          _isProcessing = false;
        });
        HapticFeedback.vibrate();
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Server connection error.";
        _isProcessing = false;
      });
    }
  }

  Future<void> _handleSignup(XFile image) async {
    try {
      setState(() => _statusMessage = "Creating secure profile...");
      
      // 1. Create a Firebase User silently (Anonymous or dummy email)
      // We will create a unique dummy email based on timestamp so they have a real Auth record
      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      String dummyEmail = "face_$timestamp@aura.com";
      String dummyPassword = "FacePassword@123";

      UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: dummyEmail, 
        password: dummyPassword
      );

      String uid = cred.user!.uid;

      // Update name
      await cred.user!.updateDisplayName(_nameController.text.trim());

      setState(() => _statusMessage = "Registering biometric data...");

      // 2. Send Face to Python API to extract math vector
      var request = http.MultipartRequest('POST', Uri.parse('$apiUrl/register_face'));
      request.fields['uid'] = uid;
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      var response = await request.send();
      
      if (response.statusCode == 200) {
        // Also save basic data to Firestore
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'name': _nameController.text.trim(),
          'email': dummyEmail,
          'role': 'visually_impaired',
          'face_login_enabled': true,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        setState(() => _statusMessage = "Registration Complete!");
        
        if (mounted) {
          HapticFeedback.heavyImpact();
          context.go('/home');
        }
      } else {
        // Cleanup if face registration failed
        await cred.user!.delete();
        setState(() {
          _statusMessage = "Failed to detect face properly.";
          _isProcessing = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = "Registration failed. Try again.";
        _isProcessing = false;
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D), // Sleek deep black
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          widget.isLogin ? 'Face ID Login' : 'Face ID Registration',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(height: Responsive.space(20)),
            
            // Text Field for Signup
            if (!widget.isLogin)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: Responsive.space(32)),
                child: TextField(
                  controller: _nameController,
                  style: GoogleFonts.poppins(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Enter your full name",
                    hintStyle: GoogleFonts.poppins(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    prefixIcon: const Icon(Icons.person_rounded, color: Color(0xFF9B59B6)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.2),
              ),

            SizedBox(height: Responsive.space(40)),

            // Futuristic Camera Scanner UI
            Expanded(
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Glowing background
                    Container(
                      width: Responsive.space(340),
                      height: Responsive.space(340),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF9B59B6).withOpacity(0.15),
                            blurRadius: 50,
                            spreadRadius: 20,
                          ),
                        ],
                      ),
                    ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                     .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 2.seconds),

                    // Camera Preview Masked in Circle
                    Container(
                      width: Responsive.space(320),
                      height: Responsive.space(320),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isProcessing ? Colors.green : const Color(0xFF9B59B6),
                          width: 4,
                        ),
                      ),
                      child: ClipOval(
                        child: _isCameraReady && _cameraController != null && _cameraController!.value.isInitialized
                            ? SizedBox(
                                width: Responsive.space(260),
                                height: Responsive.space(260),
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _cameraController!.value.previewSize?.height ?? 1080,
                                    height: _cameraController!.value.previewSize?.width ?? 1920,
                                    child: CameraPreview(_cameraController!),
                                  ),
                                ),
                              )
                            : const Center(child: CircularProgressIndicator(color: Color(0xFF9B59B6))),
                      ),
                    ),

                    // Processing Overlay
                    if (_isProcessing)
                      Container(
                        width: Responsive.space(260),
                        height: Responsive.space(260),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withOpacity(0.6),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        ),
                      ).animate().fadeIn(),

                    // Camera Flip Button
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF9B59B6).withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: _isProcessing ? null : _toggleCamera,
                          icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white),
                          tooltip: 'Flip Camera',
                        ),
                      ),
                    ).animate().fadeIn(delay: 400.ms),
                  ],
                ),
              ),
            ),

            // Status Message
            Padding(
              padding: EdgeInsets.symmetric(horizontal: Responsive.space(24)),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: _isProcessing ? Colors.green : Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ).animate(target: _isProcessing ? 1 : 0)
               .tint(color: Colors.green),
            ),

            SizedBox(height: Responsive.space(40)),

            // Capture/Scan Button
            Padding(
              padding: EdgeInsets.only(bottom: Responsive.space(40), left: Responsive.space(32), right: Responsive.space(32)),
              child: SizedBox(
                width: double.infinity,
                height: Responsive.space(56),
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _captureAndAuthenticate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9B59B6), // Purple matching the theme
                    foregroundColor: Colors.white,
                    elevation: 10,
                    shadowColor: const Color(0xFF9B59B6).withOpacity(0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.isLogin ? Icons.face_unlock_rounded : Icons.camera_alt_rounded),
                      const SizedBox(width: 12),
                      Text(
                        widget.isLogin ? 'Scan to Login' : 'Capture & Register',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2),
            ),
          ],
        ),
      ),
    );
  }
}
