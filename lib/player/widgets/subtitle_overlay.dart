import 'dart:math' as math;
import 'package:flutter/material.dart';

class SubtitleOverlay extends StatelessWidget {
  final List<String> lines;
  final double fontSize;
  final double letterSpacing;
  final FontWeight fontWeight;
  final bool isItalic;
  final bool isAllCaps;
  final String fontFamily;
  final String? fontPath;
  final Color textColor;
  final double textAlpha;
  final Color borderColor;
  final double borderAlpha;
  final double borderSize;
  final Color shadowColor;
  final double shadowAlpha;
  final double shadowDistance;
  final double shadowAngle;
  final double shadowBlur;
  final Color boxColor;
  final double boxAlpha;
  final double boxRadius;
  final double boxPaddingH;
  final double boxPaddingV;
  final bool isPreview;

  const SubtitleOverlay({
    super.key,
    required this.lines,
    required this.fontSize,
    required this.letterSpacing,
    required this.fontWeight,
    required this.isItalic,
    required this.isAllCaps,
    required this.fontFamily,
    this.fontPath,
    required this.textColor,
    required this.textAlpha,
    required this.borderColor,
    required this.borderAlpha,
    required this.borderSize,
    required this.shadowColor,
    required this.shadowAlpha,
    required this.shadowDistance,
    required this.shadowAngle,
    required this.shadowBlur,
    required this.boxColor,
    required this.boxAlpha,
    required this.boxRadius,
    required this.boxPaddingH,
    required this.boxPaddingV,
    this.isPreview = false,
  });

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();

    final double rad = shadowAngle * (math.pi / 180.0);
    final double shadowOffsetX = shadowDistance * math.cos(rad);
    final double shadowOffsetY = shadowDistance * math.sin(rad);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: boxPaddingH,
        vertical: boxPaddingV,
      ),
      decoration: BoxDecoration(
        color: boxColor.withValues(alpha: boxAlpha),
        borderRadius: BorderRadius.circular(boxRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: lines.map((line) {
          final text = isAllCaps ? line.toUpperCase() : line;
          final style = TextStyle(
            fontSize: isPreview ? 22 : fontSize,
            height: 1.4,
            letterSpacing: letterSpacing,
            fontWeight: fontWeight,
            fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
            fontFamily: fontPath != null ? 'LocalFont' : fontFamily,
          );

          return Stack(
            alignment: Alignment.center,
            children: [
              // 1. DROP SHADOW LAYER
              if (shadowDistance > 0 || shadowBlur > 0)
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: style.copyWith(
                    color: Colors.transparent,
                    shadows: [
                      Shadow(
                        color: shadowColor.withValues(alpha: shadowAlpha),
                        offset: Offset(shadowOffsetX, shadowOffsetY),
                        blurRadius: shadowBlur,
                      ),
                    ],
                  ),
                ),

              // 2. TRUE BORDER STROKE LAYER
              if (borderSize > 0)
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: style.copyWith(
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = borderSize
                      ..strokeCap = StrokeCap.round
                      ..strokeJoin = StrokeJoin.round
                      ..color = borderColor.withValues(alpha: borderAlpha),
                  ),
                ),

              // 3. FOREGROUND TEXT FILL
              Text(
                text,
                textAlign: TextAlign.center,
                style: style.copyWith(
                  color: textColor.withValues(alpha: textAlpha),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
