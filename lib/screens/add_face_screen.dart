import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/face_provider.dart';
import '../agent/agent_provider.dart';

class AddFaceScreen extends StatefulWidget {
  const AddFaceScreen({super.key});

  @override
  State<AddFaceScreen> createState() => _AddFaceScreenState();
}

class _AddFaceScreenState extends State<AddFaceScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  CameraLensDirection _currentLensDirection = CameraLensDirection.back;
  
  XFile? _capturedImage;
  bool _isSaving = false;
  
  final _nameController = TextEditingController();
  final _relationshipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AgentProvider>(context, listen: false).updateCurrentScreen('/add-face', 'Add New Face');
      _initCamera();
    });
  }

  Future<void> _initCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        debugPrint('[AddFace] Camera permission denied');
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        debugPrint('[AddFace] No cameras found');
        return;
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == _currentLensDirection,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high, // Changed to high for better face quality
        enableAudio: false,
      );

      await _cameraController!.initialize().timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw Exception("Camera initialization timed out"),
      );
      if (!mounted) return;
      setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint('[AddFace] Camera init error: $e');
      // Retry after a short delay in case previous screen's camera is still disposing
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_isCameraReady) {
          _initCamera();
        }
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
      _cameraController = null;
    }
    setState(() {
      _currentLensDirection = _currentLensDirection == CameraLensDirection.front
          ? CameraLensDirection.back
          : CameraLensDirection.front;
      _isCameraReady = false;
    });
    _initCamera();
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_isCameraReady) return;

    try {
      HapticFeedback.mediumImpact();
      final image = await _cameraController!.takePicture();
      setState(() => _capturedImage = image);
    } catch (e) {
      debugPrint('[AddFace] Capture error: $e');
    }
  }

  Future<void> _saveFace() async {
    if (_isSaving) return;

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_capturedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture a photo first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final provider = Provider.of<FaceProvider>(context, listen: false);
    final success = await provider.saveFaceWithImage(
      _nameController.text.trim(),
      _relationshipController.text.trim().isEmpty
          ? 'Friend'
          : _relationshipController.text.trim(),
      _capturedImage!,
    );

    setState(() => _isSaving = false);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_nameController.text.trim()} saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Explicitly dispose camera and wait before navigating back
      setState(() => _isCameraReady = false);
      if (_cameraController != null) {
        await _cameraController!.dispose();
        _cameraController = null;
      }
      
      if (mounted) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/face-recognition');
        }
      }
    } else if (mounted && provider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage!),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // App went to background
      cameraController.dispose();
      _cameraController = null;
      if (mounted) setState(() => _isCameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      // App came back to foreground
      if (_cameraController == null) {
        _initCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _nameController.dispose();
    _relationshipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        setState(() => _isCameraReady = false);
        if (_cameraController != null) {
          await _cameraController!.dispose();
          _cameraController = null;
        }
        if (context.mounted) {
          if (context.canPop()) {
            context.pop(result);
          } else {
            context.go('/face-recognition');
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () async {
                      setState(() => _isCameraReady = false);
                      if (_cameraController != null) {
                        await _cameraController!.dispose();
                        _cameraController = null;
                      }
                      if (mounted) {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/face-recognition');
                        }
                      }
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Expanded(
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Add ',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          TextSpan(
                            text: 'New Face',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.cyan,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isCameraReady)
                    IconButton(
                      onPressed: _switchCamera,
                      icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white, size: 24),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms),

            // Camera Preview with capture
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _capturedImage != null
                        ? Colors.green.withValues(alpha: 0.5)
                        : Colors.cyan.withValues(alpha: 0.3),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_capturedImage != null
                              ? Colors.green
                              : Colors.cyan)
                          .withValues(alpha: 0.1),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Camera feed or captured image
                      if (_isCameraReady &&
                          _cameraController != null &&
                          _cameraController!.value.isInitialized &&
                          _capturedImage == null)
                        SizedBox.expand(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _cameraController!.value.previewSize?.height ?? 1080,
                                height: _cameraController!.value.previewSize?.width ?? 1920,
                                child: CameraPreview(_cameraController!),
                              ),
                            ),
                          ),
                        )
                      else if (_capturedImage == null && !_isCameraReady)
                        const Center(
                          child: CircularProgressIndicator(color: Colors.cyan),
                        )
                      else if (_capturedImage != null)
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                color: Colors.green,
                                size: 60,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Photo captured!',
                                style: GoogleFonts.poppins(
                                  color: Colors.green,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: () {
                                  setState(() => _capturedImage = null);
                                },
                                child: Text(
                                  'Retake',
                                  style: GoogleFonts.poppins(
                                    color: Colors.cyan,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        const Center(
                          child:
                              CircularProgressIndicator(color: Colors.cyan),
                        ),

                      // Face guide circle
                      if (_capturedImage == null)
                        Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.cyan.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                        ),
                      


                      // Corner brackets
                      if (_capturedImage == null)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: CornerBracketsPainter(),
                          ),
                        ),

                      // Instruction text
                      if (_capturedImage == null)
                        Positioned(
                          bottom: 80,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.cyan.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              'Align face within circle',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                      // Capture button
                      if (_capturedImage == null)
                        Positioned(
                          bottom: 8, // Lowered capture button
                          child: GestureDetector(
                            onTap: _capturePhoto,
                            child: Container(
                              width: 68, // Made slightly larger for better reach
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.transparent,
                                border:
                                    Border.all(color: Colors.cyan, width: 3),
                              ),
                              child: Center(
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.cyan,
                                  ),
                                  child: const Icon(Icons.camera_alt,
                                      color: Colors.black, size: 22),
                                ),
                              ),
                            ),
                          ),
                        ),


                    ],
                  ),
                ),
              ),
            ).animate().fadeIn(duration: 500.ms).scale(
                  begin: const Offset(0.95, 0.95),
                ),

            // Form Section
            Flexible(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name Field
                      Text(
                        'Name',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.cyan,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _nameController,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter name',
                          hintStyle: GoogleFonts.poppins(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade900,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Relationship Field
                      Text(
                        'Relationship',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.cyan,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _relationshipController,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g., Sister, Friend, Colleague',
                          hintStyle: GoogleFonts.poppins(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade900,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                      SizedBox(
                          height: MediaQuery.of(context).size.height * 0.02),

                      // Save Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveFace,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _capturedImage != null
                                ? Colors.green.shade700
                                : Colors.cyan.shade700,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade800,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _capturedImage != null
                                      ? 'Save Face with ML'
                                      : 'Capture Photo First',
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      SizedBox(
                          height:
                              MediaQuery.of(context).padding.bottom + 16),
                    ],
                  ),
                ),
              ),
            ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1),
          ],
        ),
      ),
    ));
  }
}

// Corner brackets painter
class CornerBracketsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 20.0;
    const margin = 24.0;

    // Top-left
    canvas.drawLine(
      const Offset(margin, margin),
      const Offset(margin + cornerLength, margin),
      paint,
    );
    canvas.drawLine(
      const Offset(margin, margin),
      const Offset(margin, margin + cornerLength),
      paint,
    );

    // Top-right
    canvas.drawLine(
      Offset(size.width - margin, margin),
      Offset(size.width - margin - cornerLength, margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, margin),
      Offset(size.width - margin, margin + cornerLength),
      paint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(margin, size.height - margin),
      Offset(margin + cornerLength, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(margin, size.height - margin),
      Offset(margin, size.height - margin - cornerLength),
      paint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(size.width - margin, size.height - margin),
      Offset(size.width - margin - cornerLength, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, size.height - margin),
      Offset(size.width - margin, size.height - margin - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
