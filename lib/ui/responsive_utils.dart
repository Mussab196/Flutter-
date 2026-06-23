import 'package:flutter/material.dart';

class Responsive {
  static late double _screenWidth;
  static late double _screenHeight;
  static late double _blockWidth;
  static late double _blockHeight;
  static late bool _isSmall;
  static late bool _isMedium;
  static late bool _isLarge;

  static void init(BuildContext context) {
    final size = MediaQuery.of(context).size;
    _screenWidth = size.width;
    _screenHeight = size.height;
    _blockWidth = _screenWidth / 100;
    _blockHeight = _screenHeight / 100;

    _isSmall = _screenWidth < 360;
    _isMedium = _screenWidth >= 360 && _screenWidth < 600;
    _isLarge = _screenWidth >= 600;
  }

  static double get screenWidth => _screenWidth;
  static double get screenHeight => _screenHeight;
  static bool get isSmall => _isSmall;
  static bool get isMedium => _isMedium;
  static bool get isLarge => _isLarge;

  // Width percentage
  static double wp(double percentage) => _blockWidth * percentage;

  // Height percentage
  static double hp(double percentage) => _blockHeight * percentage;

  // Responsive font size
  static double sp(double size) {
    if (_isSmall) return size * 0.85;
    if (_isLarge) return size * 1.1;
    return size;
  }

  // Responsive icon size
  static double icon(double size) {
    if (_isSmall) return size * 0.8;
    if (_isLarge) return size * 1.15;
    return size;
  }

  // Responsive padding/margin
  static double space(double size) {
    if (_isSmall) return size * 0.8;
    if (_isLarge) return size * 1.2;
    return size;
  }

  // Responsive radius
  static double radius(double size) {
    if (_isSmall) return size * 0.85;
    if (_isLarge) return size * 1.1;
    return size;
  }
}

// Extension for easy use
extension ResponsiveExtension on num {
  double get w => Responsive.wp(toDouble());
  double get h => Responsive.hp(toDouble());
  double get sp => Responsive.sp(toDouble());
  double get icon => Responsive.icon(toDouble());
  double get r => Responsive.radius(toDouble());
}
