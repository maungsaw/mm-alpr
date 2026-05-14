import 'dart:io' show File;
import 'package:camera/camera.dart' show CameraController, availableCameras, CameraLensDirection, ResolutionPreset, CameraPreview;
import 'package:flutter/material.dart'
    show
        VoidCallback,
        StatefulWidget,
        State,
        BuildContext,
        Widget,
        Center,
        EdgeInsets,
        CircularProgressIndicator,
        debugPrint,
        MediaQuery,
        Alignment,
        BorderRadius,
        Radius,
        BoxDecoration,
        Image,
        BoxFit,
        AspectRatio,
        Container,
        Colors,
        Icons,
        Icon,
        FloatingActionButton,
        Padding,
        Stack;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart' show TextRecognizer, TextRecognitionScript, InputImage;
import 'package:intl/intl.dart' show DateFormat;

class PlateResult {
  final File? imageFile;
  final String? plate;
  final String? time;
  PlateResult({this.imageFile, this.plate, this.time});
}

// 📌 Controller to control PlateRegonizer from parent
class PlateController {
  VoidCallback? _resetCallback;

  void _attach(VoidCallback resetFn) {
    _resetCallback = resetFn;
  }

  void resetCamera() {
    _resetCallback?.call();
  }
}

class PlateRegonizer extends StatefulWidget {
  final Function(PlateResult) onPlateDetected;
  final PlateController controller;

  const PlateRegonizer({super.key, required this.onPlateDetected, required this.controller});

  @override
  State<PlateRegonizer> createState() => _PlateRegonizerState();
}

class _PlateRegonizerState extends State<PlateRegonizer> {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  File? _capturedImage;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(_resetCamera); // attach reset function
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back);
    _cameraController = CameraController(backCamera, ResolutionPreset.medium);
    await _cameraController!.initialize();

    if (!mounted) return;
    setState(() => _isCameraInitialized = true);
  }

  Future<void> _captureAndDetectPlate() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isCapturing) return;

    setState(() => _isCapturing = true);
    TextRecognizer? textRecognizer;

    try {
      final picture = await _cameraController!.takePicture();
      final imageFile = File(picture.path);

      // Initialize ML Kit text recognizer
      textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(InputImage.fromFile(imageFile));

      // Plate patterns
      final platePatterns = [
        RegExp(r'\d[A-Z]-\d{4}'),
        RegExp(r'[A-Z]{2}-\d{4}'),
        RegExp(r'[A-Z]{3}-\d{1,4}'), // first three letters pattern
        RegExp(r'\d0-\d{4}'),
      ];

      List<String> detectedPlates = [];

      for (var block in recognizedText.blocks) {
        for (var line in block.lines) {
          final text = line.text.replaceAll(' ', '').toUpperCase();
          for (var pattern in platePatterns) {
            for (final match in pattern.allMatches(text)) {
              String plate = match.group(0)!;
              // If it's the first-three-letter pattern and length > 5, remove last character
              if (pattern.pattern == r'[A-Z]{3}-\d{1,4}' && plate.length > 6) {
                plate = plate.substring(0, plate.length - 1);
              }

              detectedPlates.add(plate);
            }
          }
        }
      }

      final plate = detectedPlates.isEmpty ? "No plate detected" : detectedPlates.join('-').replaceAll('-', '');
      final time = DateFormat('HH:mm:ss').format(DateTime.now());

      setState(() => _capturedImage = imageFile);

      // Return result via callback
      widget.onPlateDetected(PlateResult(imageFile: imageFile, plate: plate, time: time));
    } catch (e) {
      debugPrint("Error detecting plate: $e");
    } finally {
      await textRecognizer?.close();
      setState(() => _isCapturing = false);
    }
  }

  // 📌 Reset camera (clear image + restart preview)
  void _resetCamera() async {
    setState(() => _capturedImage = null);
    widget.onPlateDetected(PlateResult(imageFile: null, plate: null, time: null));

    if (_cameraController != null) {
      await _initializeCamera(); // 🔄 restart preview
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceHeight = MediaQuery.of(context).size.height;

    if (!_isCameraInitialized) return const Center(child: CircularProgressIndicator());

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Container(
          height: deviceHeight / 3,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          decoration: const BoxDecoration(borderRadius: BorderRadius.all(Radius.circular(10.0))),
          child: _capturedImage != null
              ? Image.file(_capturedImage!, fit: BoxFit.cover)
              : (_cameraController != null && _cameraController!.value.isInitialized
                    ? AspectRatio(aspectRatio: _cameraController!.value.aspectRatio, child: CameraPreview(_cameraController!))
                    : const Center(child: CircularProgressIndicator())),
        ),
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: FloatingActionButton(
            onPressed: _capturedImage != null ? _resetCamera : _captureAndDetectPlate,
            child: _isCapturing ? const CircularProgressIndicator(color: Colors.white) : Icon(_capturedImage != null ? Icons.refresh : Icons.camera_alt),
          ),
        ),
      ],
    );
  }
}
