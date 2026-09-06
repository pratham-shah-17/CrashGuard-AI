import 'package:flutter/material.dart';

/// RoadSOS brand mark (shield, road, medical cross).
class RoadSOSLogo extends StatelessWidget {
  const RoadSOSLogo({
    super.key,
    this.size = 72,
    this.semanticLabel = 'RoadSOS',
  });

  static const String assetPath = 'assets/images/roadsos_logo.png';

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: semanticLabel,
      filterQuality: FilterQuality.high,
    );
  }
}
