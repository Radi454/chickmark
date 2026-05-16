import 'package:flutter/material.dart';

class ChickMarkLogo extends StatelessWidget {
  static const String assetPath = 'assets/branding/chickmark-icon.png';

  final double? logoSize;
  final bool showWordmark;
  final bool showTagline;
  final bool compact;

  const ChickMarkLogo({
    super.key,
    this.logoSize,
    this.showWordmark = true,
    this.showTagline = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final baseSize = logoSize ?? 96.0;
    final width = compact || !showWordmark ? baseSize : baseSize * 2.55;

    return Semantics(
      label: 'ChickMark logo',
      image: true,
      child: Image.asset(
        assetPath,
        width: width,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
