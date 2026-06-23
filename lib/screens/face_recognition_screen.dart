import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/face_provider.dart';
import '../agent/agent_provider.dart';

class FaceRecognitionScreen extends StatefulWidget {
  const FaceRecognitionScreen({super.key});

  @override
  State<FaceRecognitionScreen> createState() => _FaceRecognitionScreenState();
}

class _FaceRecognitionScreenState extends State<FaceRecognitionScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isStreaming = false;
  bool _isFrontCamera = false;
  bool _isSwitchingCamera = false;
  List<CameraDescription> _availableCameras = [];

  // Cache provider reference for safe dispose (avoids Provider.of crash on unmount)
  FaceProvider? _faceProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AgentProvider>(context, listen: false).updateCurrentScreen('/face-recognition', 'Face Recognition');
      _initCamera();
    });
    _faceProvider = Provider.of<FaceProvider>(context, listen: false);
  }

  Future<void> _initCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission is required for face recognition.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      _availableCameras = await availableCameras();
      if (_availableCameras.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No cameras available on this device.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Select camera based on current preference
      final targetDirection = _isFrontCamera
          ? CameraLensDirection.front
          : CameraLensDirection.back;

      final camera = _availableCameras.firstWhere(
        (c) => c.lensDirection == targetDirection,
        orElse: () => _availableCameras.first,
      );

      // Update _isFrontCamera to match actual camera selected
      _isFrontCamera = camera.lensDirection == CameraLensDirection.front;

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.nv21,
      );

      await _cameraController!.initialize().timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw Exception("Camera initialization timed out"),
      );

      if (!mounted) return;
      setState(() => _isCameraReady = true);

      _faceProvider?.setCameraInitialized(true);
      _faceProvider?.startDetecting();

      // Start processing camera frames
      _startImageStream(camera);
    } catch (e) {
      debugPrint('[FaceRecognition] Camera init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: $e (Retrying...)'),
            backgroundColor: Colors.orange,
            duration: const Duration(milliseconds: 500),
          ),
        );
        // Retry after a short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && !_isCameraReady) {
            _initCamera();
          }
        });
      }
    }
  }

  void _startImageStream(CameraDescription camera) {
    if (_cameraController == null || _isStreaming) return;

    _isStreaming = true;
    _cameraController!.startImageStream((CameraImage image) {
      _faceProvider?.processCameraFrame(image, camera);
    });
  }

  /// Switch between front and back camera
  Future<void> _switchCamera() async {
    if (_isSwitchingCamera || _availableCameras.length < 2) return;

    setState(() {
      _isSwitchingCamera = true;
      _isCameraReady = false;
    });

    try {
      // 1. Stop current image stream
      if (_isStreaming && _cameraController != null) {
        try {
          await _cameraController!.stopImageStream();
        } catch (_) {
          // Ignore — stream might already be stopped
        }
        _isStreaming = false;
      }

      // 2. Stop detecting while switching
      _faceProvider?.stopDetecting();

      // 3. Dispose current controller
      await _cameraController?.dispose();
      _cameraController = null;

      // 4. Toggle camera direction
      _isFrontCamera = !_isFrontCamera;

      // 5. Re-init with new camera
      await _initCamera();
    } catch (e) {
      debugPrint('[FaceRecognition] Camera switch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to switch camera: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSwitchingCamera = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // App went to background (e.g. user switched apps or AddFace ImagePicker opened)
      _faceProvider?.stopDetecting();
      _isStreaming = false;
      cameraController.stopImageStream().catchError((_) {});
      
      // Stop the camera to release hardware lock
      cameraController.dispose();
      _cameraController = null;
      if (mounted) setState(() => _isCameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      // App came back to foreground — reinitialize camera ONLY if we are the current screen
      if (_cameraController == null && ModalRoute.of(context)?.isCurrent == true) {
        _initCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Use cached provider reference (safe — won't crash on unmount)
    _faceProvider?.stopDetecting();
    _cameraController?.stopImageStream().catchError((_) {});
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),

            // Camera Preview with face boxes
            Expanded(
              child: _buildCameraPreview(),
            ),

            // Recognition Results
            Consumer<FaceProvider>(
              builder: (context, provider, _) {
                if (provider.currentResults.isNotEmpty) {
                  return _buildResultsPanel(provider);
                }
                return _buildStatusBar(provider);
              },
            ),

            // Bottom actions
            _buildBottomActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
          ),
          Expanded(
            child: Text(
              'Face Recognition',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 48), // Balance for centering
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildCameraPreview() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.cyan.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.cyan.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera feed or loading indicator
            if (_isCameraReady && _cameraController != null && !_isSwitchingCamera)
              CameraPreview(_cameraController!)
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.cyan),
                    const SizedBox(height: 12),
                    Text(
                      _isSwitchingCamera
                          ? 'Switching camera...'
                          : 'Initializing camera...',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),

            // Face detection boxes overlay
            Consumer<FaceProvider>(
              builder: (context, provider, _) {
                return CustomPaint(
                  painter: FaceBoxPainter(
                    faces: provider.detectedFaces,
                    results: provider.currentResults,
                    imageSize: _cameraController != null && _isCameraReady
                        ? Size(
                            _cameraController!.value.previewSize?.height ?? 480,
                            _cameraController!.value.previewSize?.width ?? 640,
                          )
                        : const Size(480, 640),
                    isFrontCamera: _isFrontCamera, // Dynamic based on active camera
                  ),
                );
              },
            ),

            // LIVE indicator + camera label
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'LIVE',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Camera indicator (front/back)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _isFrontCamera ? 'FRONT' : 'REAR',
                        style: GoogleFonts.poppins(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: Colors.cyan,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate(onPlay: (c) => c.repeat(reverse: true))
                  .fadeIn(duration: 800.ms),
            ),

            // Face count badge
            Positioned(
              top: 12,
              right: 12,
              child: Consumer<FaceProvider>(
                builder: (context, provider, _) {
                  if (provider.detectedFaces.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${provider.detectedFaces.length} face${provider.detectedFaces.length > 1 ? 's' : ''}',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms).scale(
          begin: const Offset(0.95, 0.95),
        );
  }

  Widget _buildResultsPanel(FaceProvider provider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: provider.currentResults
            .where((r) => r.name != 'Unknown')
            .map((result) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            result.name[0].toUpperCase(),
                            style: GoogleFonts.poppins(
                              color: Colors.green,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.name,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              '${result.relationship} • ${result.confidenceText} match',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.green,
                        size: 28,
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 300.ms).slideX(begin: 0.1))
            .toList(),
      ),
    );
  }

  Widget _buildStatusBar(FaceProvider provider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade900.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade800),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.cyan.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            provider.statusText,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
          const Spacer(),
          Text(
            '${provider.savedFaceCount} saved',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.cyan,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildBottomActions() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, MediaQuery.of(context).padding.bottom + 12),
      child: Row(
        children: [
          // Camera Switch button (bottom bar)
          _buildCircleAction(
            icon: Icons.cameraswitch_rounded,
            onTap: _availableCameras.length >= 2 ? _switchCamera : null,
            color: Colors.blueGrey.shade700,
          ),
          const SizedBox(width: 10),
          // Add Face button
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () async {
                // Fully release the camera before pushing the next screen
                if (_isStreaming && _cameraController != null) {
                  try {
                    await _cameraController!.stopImageStream();
                  } catch (_) {}
                  _isStreaming = false;
                }
                _faceProvider?.stopDetecting();
                
                if (_cameraController != null) {
                  await _cameraController!.dispose();
                  _cameraController = null;
                }
                
                setState(() {
                  _isCameraReady = false;
                });

                // Wait for the Add Face screen to pop back
                await context.push('/add-face');
                
                // Re-initialize camera when we come back.
                // We add a 500ms delay to ensure AddFaceScreen has fully disposed its camera hardware.
                if (mounted) {
                  await Future.delayed(const Duration(milliseconds: 500));
                  if (mounted) {
                    _initCamera();
                  }
                }
              },
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: Text(
                'Add Face',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyan.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Manage button
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _showManageFacesDialog(context),
              icon: const Icon(Icons.people_alt_outlined, size: 18),
              label: Text(
                'Manage',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade900,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade800),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2);
  }

  Widget _buildCircleAction({
    required IconData icon,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: onTap != null ? color : color.withValues(alpha: 0.3),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.grey.shade700,
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: onTap != null ? Colors.white : Colors.white38,
          size: 22,
        ),
      ),
    );
  }

  void _showManageFacesDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Consumer<FaceProvider>(
          builder: (context, provider, child) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saved Faces',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (provider.faces.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Text(
                          'No faces saved yet.',
                          style: GoogleFonts.poppins(color: Colors.white54),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: provider.faces.length,
                        itemBuilder: (context, index) {
                          final face = provider.faces[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.cyan.shade900,
                              child: Text(
                                face.name[0].toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(
                              face.name,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              '${face.relationship} • ${face.embedding.isNotEmpty ? "ML enrolled" : "No embedding"}',
                              style: GoogleFonts.poppins(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              onPressed: () => provider.deleteFace(face.id),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Paints face detection boxes and name labels on the camera preview
class FaceBoxPainter extends CustomPainter {
  final List<dynamic> faces;
  final List<RecognitionResult> results;
  final Size imageSize;
  final bool isFrontCamera;

  FaceBoxPainter({
    required this.faces,
    required this.results,
    required this.imageSize,
    required this.isFrontCamera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      final isKnown = result.name != 'Unknown';

      final paint = Paint()
        ..color = isKnown ? Colors.green : Colors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      // Scale bounding box to canvas size
      final scaleX = size.width / imageSize.width;
      final scaleY = size.height / imageSize.height;

      final rect = Rect.fromLTRB(
        isFrontCamera
            ? size.width - result.boundingBox.right * scaleX
            : result.boundingBox.left * scaleX,
        result.boundingBox.top * scaleY,
        isFrontCamera
            ? size.width - result.boundingBox.left * scaleX
            : result.boundingBox.right * scaleX,
        result.boundingBox.bottom * scaleY,
      );

      // Draw rounded rect
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        paint,
      );

      // Draw name label
      if (isKnown) {
        final labelPaint = Paint()
          ..color = Colors.green.withValues(alpha: 0.85);

        final labelRect = Rect.fromLTWH(
          rect.left,
          rect.top - 24,
          rect.width,
          22,
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(labelRect, const Radius.circular(6)),
          labelPaint,
        );

        final textPainter = TextPainter(
          text: TextSpan(
            text: '${result.name} ${result.confidenceText}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: rect.width);
        textPainter.paint(
          canvas,
          Offset(rect.left + 4, rect.top - 22),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant FaceBoxPainter oldDelegate) {
    return oldDelegate.results != results || oldDelegate.faces != faces;
  }
}
