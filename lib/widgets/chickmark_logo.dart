import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// Full horizontal ChickMark logo.
/// Renders `assets/images/logo.png` when present; falls back to a
/// Flutter-drawn replica that mirrors the actual logo layout.
class ChickMarkLogo extends StatelessWidget {
  final double height;

  const ChickMarkLogo({super.key, this.height = 80});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _RenderedLogo(height: height),
    );
  }
}

/// Small icon-only version for app bars and compact contexts.
/// Uses `assets/images/icon.png` when present; falls back to a styled chick.
class ChickMarkIcon extends StatelessWidget {
  final double size;
  final Color color;

  const ChickMarkIcon({
    super.key,
    this.size = 32,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/icon.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => _ChickFallback(size: size, color: color),
    );
  }
}

// ── Fallback: Flutter-drawn logo ──────────────────────────────────────────────

class _RenderedLogo extends StatelessWidget {
  final double height;

  const _RenderedLogo({required this.height});

  @override
  Widget build(BuildContext context) {
    final iconSize = height * 0.72;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Chick circle
        Container(
          width: iconSize,
          height: iconSize,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text('🐥', style: TextStyle(fontSize: iconSize * 0.54)),
              Positioned(
                bottom: iconSize * 0.12,
                right: iconSize * 0.08,
                child: Icon(
                  Icons.check,
                  size: iconSize * 0.28,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: height * 0.14),
        // Text block
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ChickMark',
              style: TextStyle(
                fontSize: height * 0.38,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'HATCHERY AUDIT',
              style: TextStyle(
                fontSize: height * 0.155,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
                letterSpacing: 2.8,
              ),
            ),
            SizedBox(height: height * 0.06),
            Container(
              height: 2,
              width: height * 1.7,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChickFallback extends StatelessWidget {
  final double size;
  final Color color;

  const _ChickFallback({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text('🐥', style: TextStyle(fontSize: size * 0.62)),
          Positioned(
            bottom: 1,
            right: 1,
            child: Icon(Icons.check_circle, size: size * 0.36, color: AppTheme.primary),
          ),
        ],
      ),
    );
  }
}

/// App-bar title: small icon + "ChickMark" text.
class ChickMarkAppBarTitle extends StatelessWidget {
  const ChickMarkAppBarTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/icon.png',
          height: 28,
          errorBuilder: (_, _, _) => const Text('🐥', style: TextStyle(fontSize: 22)),
        ),
        const SizedBox(width: 8),
        const Text(
          'ChickMark',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ],
    );
  }
}
