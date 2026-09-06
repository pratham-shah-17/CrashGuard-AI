import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// Global app logger. In release builds only [Level.warning] and above are printed,
/// so debug/diagnostic traces (including location-heavy strings) are not emitted.
final Logger appLog = Logger(
  level: kReleaseMode ? Level.warning : Level.debug,
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 6,
    lineLength: 100,
    colors: !kReleaseMode,
    printEmojis: !kReleaseMode,
    dateTimeFormat: DateTimeFormat.none,
  ),
);
