import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'dart:io';

/// Converts CameraImage to img.Image for TFLite processing
img.Image? convertCameraImageToImage(CameraImage image) {
  try {
    if (Platform.isIOS || image.format.group == ImageFormatGroup.bgra8888) {
      return _convertBGRA8888(image);
    } else if (image.planes.length == 1) {
      return _convertNV21SinglePlane(image);
    } else if (image.format.group == ImageFormatGroup.yuv420 && image.planes.length == 3) {
      return _convertYUV420(image);
    } else {
      // Fallback or NV21
      return _convertNV21(image);
    }
  } catch (e) {
    print('Error converting camera image: $e');
    return null;
  }
}

img.Image _convertBGRA8888(CameraImage image) {
  return img.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: image.planes[0].bytes.buffer,
    order: img.ChannelOrder.bgra,
  );
}

img.Image _convertYUV420(CameraImage image) {
  final width = image.width;
  final height = image.height;
  
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final yBuffer = yPlane.bytes;
  final uBuffer = uPlane.bytes;
  final vBuffer = vPlane.bytes;

  final yRowStride = yPlane.bytesPerRow;
  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel!;

  final imgResult = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yIndex = y * yRowStride + x;
      final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

      final int yp = yBuffer[yIndex];
      final int up = uBuffer[uvIndex];
      final int vp = vBuffer[uvIndex];

      int r = (yp + vp * 1436 / 1024 - 179).round();
      int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91).round();
      int b = (yp + up * 1814 / 1024 - 227).round();

      r = r.clamp(0, 255);
      g = g.clamp(0, 255);
      b = b.clamp(0, 255);

      imgResult.setPixelRgb(x, y, r, g, b);
    }
  }

  return imgResult;
}

img.Image _convertNV21(CameraImage image) {
  final width = image.width;
  final height = image.height;
  
  if (image.planes.length == 1) {
    return _convertNV21SinglePlane(image);
  }
  
  final yPlane = image.planes[0];
  final vuPlane = image.planes[1]; // NV21 has V and U interleaved

  final yBuffer = yPlane.bytes;
  final vuBuffer = vuPlane.bytes;

  final yRowStride = yPlane.bytesPerRow;
  final vuRowStride = vuPlane.bytesPerRow;

  final imgResult = img.Image(width: width, height: height);

  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yIndex = y * yRowStride + x;
      final uvIndex = (y ~/ 2) * vuRowStride + (x ~/ 2) * 2;

      final int yp = yBuffer[yIndex];
      final int vp = vuBuffer[uvIndex];
      final int up = vuBuffer[uvIndex + 1];

      int r = (yp + vp * 1436 / 1024 - 179).round();
      int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91).round();
      int b = (yp + up * 1814 / 1024 - 227).round();

      r = r.clamp(0, 255);
      g = g.clamp(0, 255);
      b = b.clamp(0, 255);

      imgResult.setPixelRgb(x, y, r, g, b);
    }
  }

  return imgResult;
}

img.Image _convertNV21SinglePlane(CameraImage image) {
  final width = image.width;
  final height = image.height;
  final plane = image.planes[0];
  final bytes = plane.bytes;
  final bytesPerRow = plane.bytesPerRow;
  
  final ySize = bytesPerRow * height;
  final imgResult = img.Image(width: width, height: height);
  
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final yIndex = y * bytesPerRow + x;
      final uvIndex = ySize + (y ~/ 2) * bytesPerRow + (x ~/ 2) * 2;
      
      if (yIndex >= bytes.length || uvIndex + 1 >= bytes.length) {
        continue;
      }
      
      int yp = bytes[yIndex];
      int vp = bytes[uvIndex];
      int up = bytes[uvIndex + 1];
      
      int r = (yp + vp * 1436 / 1024 - 179).round();
      int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91).round();
      int b = (yp + up * 1814 / 1024 - 227).round();
      
      imgResult.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
    }
  }
  return imgResult;
}
