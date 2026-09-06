import 'package:flutter/material.dart';

/// Blueprint §04 — Emergency-grade palette (solid colours only in UI chrome).
abstract final class RoadSosColors {
  static const Color abyss = Color(0xFF080A0D);
  static const Color bloodRed = Color(0xFFE8281A);
  static const Color meshTeal = Color(0xFF00B8A0);
  static const Color amber = Color(0xFFF59220);

  /// UI chrome borders / dividers on abyss.
  static Color get borderSubtle => Colors.white.withValues(alpha: 0.07);
}

/// Layout constants (8px grid, minimum touch targets).
abstract final class RoadSosLayout {
  static const double grid = 8;
  static const double screenPaddingH = 20;
  static const double cardPadding = 20;
  static const double minTap = 56;
  static const double sosButtonDiameter = 160;
}

/// Motion — blueprint: 180ms emergency surfaces, 280ms non-emergency; ease-out cubic.
abstract final class RoadSosMotion {
  static const Duration emergencyTransition = Duration(milliseconds: 180);
  static const Duration normalTransition = Duration(milliseconds: 280);
  static const Curve easing = Curves.easeOutCubic;
}
