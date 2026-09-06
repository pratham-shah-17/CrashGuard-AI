import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'roadsos_tokens.dart';

/// Material 3 themes aligned to Implementation Blueprint §04.
abstract final class RoadSosTheme {
  static ThemeData buildOperationalDark() {
    final colorScheme = ColorScheme.dark(
      brightness: Brightness.dark,
      primary: RoadSosColors.meshTeal,
      onPrimary: Colors.white,
      secondary: RoadSosColors.amber,
      onSecondary: Colors.black,
      surface: RoadSosColors.abyss,
      onSurface: Colors.white,
      error: RoadSosColors.bloodRed,
      onError: Colors.white,
      outline: RoadSosColors.borderSubtle,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: RoadSosColors.abyss,
      canvasColor: RoadSosColors.abyss,
      dividerColor: RoadSosColors.borderSubtle,
      splashFactory: InkRipple.splashFactory,
      cardTheme: CardThemeData(
        color: RoadSosColors.abyss,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: RoadSosColors.borderSubtle),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(RoadSosLayout.minTap),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          foregroundColor: Colors.white,
          backgroundColor: RoadSosColors.meshTeal,
        ),
      ),
    );

    final text = base.textTheme;
    return base.copyWith(
      textTheme: text.copyWith(
        displayLarge: GoogleFonts.bebasNeue(
          fontSize: 40,
          fontWeight: FontWeight.w400,
          color: Colors.white,
          letterSpacing: 2,
        ),
        displayMedium: GoogleFonts.bebasNeue(
          fontSize: 32,
          fontWeight: FontWeight.w400,
          color: Colors.white,
        ),
        titleLarge: GoogleFonts.bebasNeue(
          fontSize: 22,
          fontWeight: FontWeight.w400,
          color: Colors.white,
        ),
        bodyLarge: GoogleFonts.notoSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.4,
          color: Colors.white,
        ),
        bodyMedium: GoogleFonts.notoSans(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: Colors.white,
        ),
        labelLarge: GoogleFonts.dmMono(
          fontWeight: FontWeight.w500,
          color: RoadSosColors.meshTeal,
        ),
        labelMedium: GoogleFonts.dmMono(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: Colors.white,
        ),
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }

  /// Full SOS / panic override — blood-red focal hierarchy.
  static ThemeData buildEmergencyDark() {
    final base = buildOperationalDark();
    final cs = base.colorScheme.copyWith(
      primary: RoadSosColors.bloodRed,
      error: RoadSosColors.bloodRed,
      surface: Colors.black,
    );
    return base.copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: Colors.black,
      canvasColor: Colors.black,
    );
  }
}
