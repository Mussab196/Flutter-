import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../providers/ocr_provider.dart';
import '../agent/agent_provider.dart';

class OcrReaderScreen extends StatefulWidget {
  const OcrReaderScreen({super.key});

  @override
  State<OcrReaderScreen> createState() => _OcrReaderScreenState();
}

class _OcrReaderScreenState extends State<OcrReaderScreen>
    with WidgetsBindingObserver {
  late OcrProvider _ocrProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AgentProvider>(context, listen: false).updateCurrentScreen('/ocr-reader', 'Text Reader');
      _ocrProvider = Provider.of<OcrProvider>(context, listen: false);
      _ocrProvider.initCamera();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Stop operations and free camera hardware when app goes to background
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _ocrProvider.cancelOperations();
      if (_ocrProvider.isCameraInitialized) {
        _ocrProvider.disposeCamera();
      }
    } else if (state == AppLifecycleState.resumed) {
      // Reacquire the camera hardware when app comes back
      if (!_ocrProvider.isCameraInitialized) {
        _ocrProvider.initCamera();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Cancel all ongoing operations when screen closes
    _ocrProvider.cancelOperations();
    _ocrProvider.disposeCamera();
    super.dispose();
  }

  void _captureAndRead() async {
    final ocrProvider = Provider.of<OcrProvider>(context, listen: false);
    final text = await ocrProvider.captureAndRecognize();

    if (text.isNotEmpty) {
      // The UI will update automatically because recognizedText is not empty
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Text(ocrProvider.errorMessage ?? 'No text detected'),
              ],
            ),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _readAloud() async {
    final ocrProvider = Provider.of<OcrProvider>(context, listen: false);
    if (ocrProvider.recognizedText.isNotEmpty) {
      await ocrProvider.speakRecognizedText();
    } else {
      final text = await ocrProvider.captureAndRecognize();
      if (text.isNotEmpty) {
        await ocrProvider.speakText(text);
        // The UI will update automatically because recognizedText is not empty
      }
    }
  }

  void _stopReading() async {
    final ocrProvider = Provider.of<OcrProvider>(context, listen: false);
    await ocrProvider.stopSpeaking();
  }

  void _pickFromGallery() async {
    final ocrProvider = Provider.of<OcrProvider>(context, listen: false);
    final image = await ocrProvider.pickImageFromGallery();
    if (image != null) {
      final text = await ocrProvider.recognizeText(image);
      if (text.isNotEmpty) {
        // The UI will update automatically because recognizedText is not empty
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ocrProvider = Provider.of<OcrProvider>(context);

    return Scaffold(
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
                    onPressed: () {
                      ocrProvider.stopSpeaking();
                      context.pop();
                    },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      'Text Reader',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.cyan,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    onPressed: _pickFromGallery,
                    icon: const Icon(Icons.photo_library_rounded,
                        color: Colors.white70),
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 400.ms),

            // Camera View or Recognized Text
            Expanded(
              child:
                  ocrProvider.recognizedText.isNotEmpty
                      ? _buildRecognizedTextView(ocrProvider)
                      : _buildCameraView(ocrProvider),
            ),

            // Bottom Controls
            _buildBottomControls(ocrProvider),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraView(OcrProvider ocrProvider) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade800, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Camera Preview
            if (ocrProvider.isCameraInitialized &&
                ocrProvider.cameraController != null)
              SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: CameraPreview(ocrProvider.cameraController!),
              )
            else
              Container(
                width: double.infinity,
                height: double.infinity,
                color: const Color(0xFF0D0D0D),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.cyan),
                ),
              ),

            // Scanner Frame
            Positioned.fill(child: CustomPaint(painter: ScannerFramePainter())),

            // LIVE Indicator
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text('LIVE',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),

            // Processing Indicator
            if (ocrProvider.isProcessing)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.cyan),
                      const SizedBox(height: 16),
                      Text('Scanning text...',
                          style: GoogleFonts.poppins(
                              color: Colors.white, fontSize: 14)),
                    ],
                  ),
                ),
              ),

            // Instruction Text
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Column(
                children: [
                  Text('Point camera at text',
                      style: GoogleFonts.poppins(
                          fontSize: 13, color: Colors.white70),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text('Tap "Capture" or "Read Aloud"',
                      style:
                          GoogleFonts.poppins(fontSize: 13, color: Colors.cyan),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms);
  }

  Widget _buildRecognizedTextView(OcrProvider ocrProvider) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade800, width: 1),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.text_fields_rounded,
                    color: Colors.cyan, size: 24),
                const SizedBox(width: 12),
                Text('Recognized Text',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    ocrProvider.clearText();
                    // UI will update automatically because recognizedText becomes empty
                  },
                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                ),
              ],
            ),
          ),
          // Show character count and word count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '${ocrProvider.recognizedText.length} characters • ${ocrProvider.recognizedText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} words',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'OCR',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade700),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  ocrProvider.recognizedText,
                  style: const TextStyle(
                    fontFamily:
                        'monospace', // Monospace for exact text representation
                    fontSize: 15,
                    color: Colors.white,
                    height: 1.5,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
          if (ocrProvider.isSpeaking)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.cyan)),
                  const SizedBox(width: 12),
                  Text('Reading aloud...',
                      style: GoogleFonts.poppins(
                          color: Colors.cyan, fontSize: 14)),
                ],
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildBottomControls(OcrProvider ocrProvider) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 8, 24, MediaQuery.of(context).padding.bottom + 16),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: ocrProvider.isProcessing ? null : _captureAndRead,
              icon: const Icon(Icons.camera_alt_rounded),
              label: Text('Capture',
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: ocrProvider.isProcessing
                  ? null
                  : (ocrProvider.isSpeaking ? _stopReading : _readAloud),
              icon: Icon(ocrProvider.isSpeaking
                  ? Icons.stop_rounded
                  : Icons.volume_up_rounded),
              label: Text(ocrProvider.isSpeaking ? 'Stop' : 'Read Aloud',
                  style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    ocrProvider.isSpeaking ? Colors.red : Colors.cyan,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.2);
  }
}

// Custom painter for scanner frame corners
class ScannerFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    const margin = 20.0;

    // Top-left corner
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

    // Top-right corner
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

    // Bottom-left corner
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

    // Bottom-right corner
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
