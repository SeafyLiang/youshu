import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'ui.dart';

enum MascotMood { signature, happy, curious }

/// 柔雾哑光萌宠主题矢量插画（零外部版权风险、同步首帧渲染）。
class ThemeMascot extends StatelessWidget {
  final AppThemeStyle style;
  final double size;
  final MascotMood mood;

  const ThemeMascot({
    super.key,
    required this.style,
    this.size = 56,
    this.mood = MascotMood.signature,
  });

  @override
  Widget build(BuildContext context) {
    final svg = _mascotSvg(style, mood);
    if (svg == null) return const SizedBox.shrink();
    return SvgPicture.string(
      svg,
      width: size,
      height: size * 0.88,
      fit: BoxFit.contain,
    );
  }
}

/// 主题专属小徽标图标（猫爪 / 小骨头 / 嫩竹叶 / 小柚子 / 四角星 / 四叶草）。
class ThemeMotifIcon extends StatelessWidget {
  final AppThemeStyle style;
  final double size;
  final Color? color;

  const ThemeMotifIcon({
    super.key,
    required this.style,
    this.size = 13,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final svg = _motifSvg(style);
    if (svg == null) return const SizedBox.shrink();
    final tint = color ?? AppPalette.of(context).brandColor;
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}

/// 粗标记笔柔雾半透明高光划痕（用于柔雾哑光萌宠主题的关键数字下沿点缀）。
class MarkerHighlight extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double height;
  final double bottom;

  const MarkerHighlight({
    super.key,
    required this.child,
    this.color,
    this.height = 9,
    this.bottom = 1,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final swipe = color ?? p.markerSwipe;
    if (swipe == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -2,
          right: -3,
          bottom: bottom,
          height: height,
          child: Transform(
            transform: Matrix4.skewX(-0.16),
            alignment: Alignment.center,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: swipe,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(7),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(3),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// 轻量手账纸底纹绘制器（配合 RepaintBoundary，不影响 120Hz 滚动性能）。
class ThemeWallpaperPainter extends CustomPainter {
  final AppThemeStyle style;
  final Color patternColor;
  final Color auraColor;
  final bool isDark;

  const ThemeWallpaperPainter({
    required this.style,
    required this.patternColor,
    required this.auraColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!style.isCute) return;

    // 1. 顶部柔雾光晕
    final auraRect = Rect.fromLTWH(0, 0, size.width, 220);
    final auraPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.72, -1.0),
        radius: 1.25,
        colors: [
          auraColor.withValues(alpha: isDark ? 0.14 : 0.34),
          auraColor.withValues(alpha: 0),
        ],
      ).createShader(auraRect);
    canvas.drawRect(auraRect, auraPaint);

    // 2. 低饱和手账纸微底纹
    final fill = Paint()
      ..color = patternColor.withValues(alpha: isDark ? 0.065 : 0.082)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = patternColor.withValues(alpha: isDark ? 0.075 : 0.095)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    const step = 70.0;
    final cols = (size.width / step).ceil() + 1;
    final rows = (size.height / step).ceil() + 1;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final ox = c * step + (r.isOdd ? step * 0.45 : 14);
        final oy = r * step + 18;
        _drawMotif(canvas, Offset(ox, oy), fill, stroke);
        // 辅助极小圆点增加手账纸呼吸感
        canvas.drawCircle(Offset(ox + 34, oy + 26), 1.5, fill);
      }
    }
  }

  void _drawMotif(Canvas canvas, Offset center, Paint fill, Paint stroke) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    switch (style) {
      case AppThemeStyle.cat:
        canvas.rotate(-0.2);
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(0, 3), width: 7.5, height: 5.5),
          fill,
        );
        canvas.drawCircle(const Offset(-4.2, -1.2), 1.5, fill);
        canvas.drawCircle(const Offset(-1.5, -3.0), 1.5, fill);
        canvas.drawCircle(const Offset(1.5, -3.0), 1.5, fill);
        canvas.drawCircle(const Offset(4.2, -1.2), 1.5, fill);
      case AppThemeStyle.dog:
        canvas.rotate(-0.28);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: 9.5, height: 3.4),
            const Radius.circular(1.7),
          ),
          fill,
        );
        canvas.drawCircle(const Offset(-4.8, -1.8), 2.0, fill);
        canvas.drawCircle(const Offset(-4.8, 1.8), 2.0, fill);
        canvas.drawCircle(const Offset(4.8, -1.8), 2.0, fill);
        canvas.drawCircle(const Offset(4.8, 1.8), 2.0, fill);
      case AppThemeStyle.panda:
        final leaf = Path()
          ..moveTo(-6, 5)
          ..quadraticBezierTo(-2, -3, 7, -5)
          ..quadraticBezierTo(4, 2, -6, 5)
          ..close();
        canvas.drawPath(leaf, fill);
        final leaf2 = Path()
          ..moveTo(0, 6)
          ..quadraticBezierTo(6, 3, 10, 6)
          ..quadraticBezierTo(5, 9, 0, 6)
          ..close();
        canvas.drawPath(leaf2, fill);
      case AppThemeStyle.capybara:
        canvas.drawCircle(Offset.zero, 5.5, stroke);
        canvas.drawLine(const Offset(0, -4.5), const Offset(0, 4.5), stroke);
        canvas.drawLine(const Offset(-4.5, 0), const Offset(4.5, 0), stroke);
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(20, 14), width: 13, height: 5),
          stroke,
        );
      case AppThemeStyle.taro:
        final star = Path();
        for (var i = 0; i < 4; i++) {
          final a = i * math.pi / 2;
          final p1 = Offset(math.cos(a) * 5.2, math.sin(a) * 5.2);
          final p2 = Offset(
            math.cos(a + math.pi / 4) * 1.6,
            math.sin(a + math.pi / 4) * 1.6,
          );
          if (i == 0) {
            star.moveTo(p1.dx, p1.dy);
          } else {
            star.lineTo(p1.dx, p1.dy);
          }
          star.lineTo(p2.dx, p2.dy);
        }
        star.close();
        canvas.drawPath(star, fill);
      case AppThemeStyle.matcha:
        canvas.drawCircle(const Offset(0, -2.8), 2.5, fill);
        canvas.drawCircle(const Offset(2.8, 0), 2.5, fill);
        canvas.drawCircle(const Offset(0, 2.8), 2.5, fill);
        canvas.drawCircle(const Offset(-2.8, 0), 2.5, fill);
      case AppThemeStyle.emerald:
      case AppThemeStyle.mono:
      case AppThemeStyle.oat:
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ThemeWallpaperPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.patternColor != patternColor ||
      oldDelegate.auraColor != auraColor ||
      oldDelegate.isDark != isDark;
}

String? _motifSvg(AppThemeStyle style) => switch (style) {
  AppThemeStyle.cat =>
    '<svg viewBox="0 0 24 24" fill="#000"><ellipse cx="12" cy="15.5" rx="4.8" ry="3.8"/><circle cx="6.5" cy="10.8" r="2"/><circle cx="10.1" cy="8.2" r="2"/><circle cx="13.9" cy="8.2" r="2"/><circle cx="17.5" cy="10.8" r="2"/></svg>',
  AppThemeStyle.dog =>
    '<svg viewBox="0 0 24 24" fill="#000"><rect x="6.5" y="10" width="11" height="4" rx="2"/><circle cx="6.5" cy="9.6" r="2.4"/><circle cx="6.5" cy="14.4" r="2.4"/><circle cx="17.5" cy="9.6" r="2.4"/><circle cx="17.5" cy="14.4" r="2.4"/></svg>',
  AppThemeStyle.panda =>
    '<svg viewBox="0 0 24 24" fill="#000"><path d="M5 19C9 15 13 11 19 5" stroke="#000" stroke-width="2" stroke-linecap="round"/><path d="M12.5 11.5C12.5 7.2 15.2 5.2 18.8 5.2C18.8 9 16.6 11.5 12.5 11.5Z"/><path d="M10.5 13.8C6.8 13 5 10.5 5 7.5C8.2 7.5 10.5 10.2 10.5 13.8Z" opacity="0.8"/></svg>',
  AppThemeStyle.capybara =>
    '<svg viewBox="0 0 24 24" fill="#000"><circle cx="12" cy="14" r="6.5"/><path d="M12 7.4C13.5 4.4 16.5 4.4 18 6.4C15.8 8 13.6 8.1 12 7.4Z" opacity="0.85"/></svg>',
  AppThemeStyle.taro =>
    '<svg viewBox="0 0 24 24" fill="#000"><path d="M12 3L14.1 9.9L21 12L14.1 14.1L12 21L9.9 14.1L3 12L9.9 9.9L12 3Z"/></svg>',
  AppThemeStyle.matcha =>
    '<svg viewBox="0 0 24 24" fill="#000"><circle cx="12" cy="8" r="3.6"/><circle cx="16" cy="12" r="3.6"/><circle cx="12" cy="16" r="3.6"/><circle cx="8" cy="12" r="3.6"/><path d="M12 16C12 19 13.8 20.8 15.5 21.5" stroke="#000" stroke-width="1.8" stroke-linecap="round" fill="none"/></svg>',
  _ => null,
};

String? _mascotSvg(AppThemeStyle style, MascotMood mood) {
  switch (style) {
    case AppThemeStyle.cat:
      final eyes = switch (mood) {
        MascotMood.happy =>
          '<path d="M31 48C33.5 43.5 39.5 43.5 42 48" stroke="#4D2F1C" stroke-width="2.6" stroke-linecap="round"/><path d="M62 48C64.5 43.5 70.5 43.5 73 48" stroke="#4D2F1C" stroke-width="2.6" stroke-linecap="round"/>',
        MascotMood.curious =>
          '<circle cx="37" cy="48" r="4.6" fill="#3B2314"/><circle cx="35.5" cy="46.2" r="1.7" fill="#FFF"/><circle cx="38.5" cy="49.8" r="0.9" fill="#FFF"/><circle cx="67" cy="48" r="4.6" fill="#3B2314"/><circle cx="65.5" cy="46.2" r="1.7" fill="#FFF"/><circle cx="68.5" cy="49.8" r="0.9" fill="#FFF"/>',
        MascotMood.signature =>
          '<ellipse cx="37" cy="48" rx="4.5" ry="5" fill="#3B2314"/><circle cx="35.3" cy="46" r="1.8" fill="#FFFFFF"/><circle cx="38.4" cy="50" r="0.95" fill="#FFFFFF"/><path d="M61.5 48.5C64 44.2 69.5 44.2 72 48.5" stroke="#4D2F1C" stroke-width="2.6" stroke-linecap="round"/>',
      };
      final mouth = mood == MascotMood.curious
          ? '<circle cx="52" cy="56.5" r="2.2" fill="#F08B84" stroke="#6E4124" stroke-width="1.3"/>'
          : '<path d="M46.5 55C48 57.6 50.8 57.4 52 54.6C53.2 57.4 56 57.6 57.5 55" stroke="#6E4124" stroke-width="1.9" stroke-linecap="round"/><path d="M49.8 57.2C49.8 60.4 54.2 60.4 54.2 57.2Z" fill="#FF9896"/>';
      return '<svg viewBox="0 0 104 92" fill="none" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M90 14L91.8 18.2L96 20L91.8 21.8L90 26L88.2 21.8L84 20L88.2 18.2L90 14Z" fill="#FFD980"/>'
          '<g transform="rotate(-3 52 48)">'
          '<path d="M21 41L16 14C15.5 10.8 19.2 9 22 11L40 24Z" fill="#F6B982" stroke="#7A4C2C" stroke-width="1.8" stroke-linejoin="round"/>'
          '<path d="M23.5 34L21 18.5L34 27Z" fill="#FFD6CA"/>'
          '<path d="M83 41L88 14C88.5 10.8 84.8 9 82 11L64 24Z" fill="#F6B982" stroke="#7A4C2C" stroke-width="1.8" stroke-linejoin="round"/>'
          '<path d="M80.5 34L83 18.5L70 27Z" fill="#FFD6CA"/>'
          '<path d="M16 51C16 32 31 22 52 22C73 22 88 32 88 51C88 67 74 76 52 76C30 76 16 67 16 51Z" fill="#F8C692" stroke="#7A4C2C" stroke-width="1.8"/>'
          '<ellipse cx="52" cy="60" rx="23" ry="14" fill="#FFF9F0"/>'
          '<path d="M52 23V31M44 24.5L46 30.5M60 24.5L58 30.5" stroke="#D17E48" stroke-width="2.3" stroke-linecap="round"/>'
          '<path d="M18 48L24 49.5M18 54L24 54M86 48L80 49.5M86 54L80 54" stroke="#D17E48" stroke-width="1.8" stroke-linecap="round"/>'
          '$eyes'
          '<ellipse cx="27" cy="55" rx="5.5" ry="3.2" fill="#FF9E96" opacity="0.65"/>'
          '<ellipse cx="77" cy="55" rx="5.5" ry="3.2" fill="#FF9E96" opacity="0.65"/>'
          '<path d="M49.5 52C49.5 50.8 54.5 50.8 54.5 52L52 54.8Z" fill="#EC8282"/>'
          '$mouth'
          '<path d="M32 73C42 78 62 78 72 73" stroke="#E88072" stroke-width="4.2" stroke-linecap="round"/>'
          '<circle cx="52" cy="78" r="4.5" fill="#FFE082" stroke="#9A6D24" stroke-width="1.4"/>'
          '</g>'
          '<ellipse cx="28" cy="80" rx="9.5" ry="6.8" fill="#FFF9F0" stroke="#7A4C2C" stroke-width="1.7"/>'
          '<g transform="translate(68 65) rotate(14)">'
          '<ellipse cx="9" cy="9" rx="9.5" ry="7.2" fill="#FFF9F0" stroke="#7A4C2C" stroke-width="1.7"/>'
          '<circle cx="9" cy="10" r="2.2" fill="#FFB6B6"/>'
          '<circle cx="5.5" cy="7" r="1.1" fill="#FFB6B6"/>'
          '<circle cx="9" cy="6" r="1.1" fill="#FFB6B6"/>'
          '<circle cx="12.5" cy="7" r="1.1" fill="#FFB6B6"/>'
          '</g></svg>';

    case AppThemeStyle.dog:
      final eyes = mood == MascotMood.happy
          ? '<path d="M31 47.5C33.5 43 39.5 43 42 47.5" stroke="#472D12" stroke-width="2.5" stroke-linecap="round"/><path d="M62 47.5C64.5 43 70.5 43 73 47.5" stroke="#472D12" stroke-width="2.5" stroke-linecap="round"/>'
          : '<ellipse cx="37" cy="47.5" rx="4.2" ry="4.8" fill="#3B240E"/><circle cx="35.4" cy="45.6" r="1.7" fill="#FFF"/><ellipse cx="67" cy="47.5" rx="4.2" ry="4.8" fill="#3B240E"/><circle cx="65.4" cy="45.6" r="1.7" fill="#FFF"/>';
      final tongue = mood == MascotMood.curious
          ? ''
          : '<path d="M48.5 61.5C48.5 67 55.5 67 55.5 61.5Z" fill="#FF949B" stroke="#BD5E65" stroke-width="1.2"/>';
      return '<svg viewBox="0 0 104 92" fill="none" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M10 24L15 27M8 31L13 32" stroke="#DFB460" stroke-width="2" stroke-linecap="round"/>'
          '<g transform="rotate(3 52 48)">'
          '<path d="M22 40L19 13C18.8 10 22.5 8.5 25 10.6L42 24Z" fill="#EBB86E" stroke="#785124" stroke-width="1.8" stroke-linejoin="round"/>'
          '<path d="M24.5 34L23 18.5L35 27Z" fill="#FFF5E2"/>'
          '<path d="M82 40L91 16C92 13 88.5 10.5 85.5 12.2L65 24Z" fill="#EBB86E" stroke="#785124" stroke-width="1.8" stroke-linejoin="round"/>'
          '<path d="M79 34L84 20.5L70 27Z" fill="#FFF5E2"/>'
          '<path d="M14 54C14 34 30 22 52 22C74 22 90 34 90 54C90 70 76 77 52 77C28 77 14 70 14 54Z" fill="#F0C37C" stroke="#785124" stroke-width="1.8"/>'
          '<path d="M17 55C18 45 31 42 41 49C45 52 48 51 52 51C56 51 59 52 63 49C73 42 86 45 87 55C87 69 74 76 52 76C30 76 17 69 17 55Z" fill="#FFFBF3"/>'
          '<ellipse cx="38" cy="36.5" rx="4.4" ry="2.7" transform="rotate(-14 38 36.5)" fill="#FFF9EA"/>'
          '<ellipse cx="66" cy="36.5" rx="4.4" ry="2.7" transform="rotate(14 66 36.5)" fill="#FFF9EA"/>'
          '$eyes'
          '<ellipse cx="26" cy="56" rx="5.5" ry="3.2" fill="#FF9C8C" opacity="0.58"/>'
          '<ellipse cx="78" cy="56" rx="5.5" ry="3.2" fill="#FF9C8C" opacity="0.58"/>'
          '<ellipse cx="52" cy="53.5" rx="4.5" ry="3.2" fill="#3B2310"/>'
          '<ellipse cx="50.6" cy="52.4" rx="1.3" ry="0.7" fill="#FFF" opacity="0.6"/>'
          '<path d="M44 59.5C46.8 63 50.5 62.5 52 59C53.5 62.5 57.2 63 60 59.5" stroke="#5E3916" stroke-width="1.9" stroke-linecap="round"/>'
          '$tongue'
          '<path d="M31 73L52 86L73 73C63 77 41 77 31 73Z" fill="#E37C70" stroke="#8C423A" stroke-width="1.6" stroke-linejoin="round"/>'
          '<circle cx="45" cy="77.5" r="1.4" fill="#FFF8EE"/><circle cx="52" cy="80.8" r="1.4" fill="#FFF8EE"/><circle cx="59" cy="77.5" r="1.4" fill="#FFF8EE"/>'
          '</g>'
          '<ellipse cx="27" cy="80" rx="9.5" ry="6.8" fill="#FFFBF3" stroke="#785124" stroke-width="1.7"/>'
          '<ellipse cx="77" cy="80" rx="9.5" ry="6.8" fill="#FFFBF3" stroke="#785124" stroke-width="1.7"/>'
          '</svg>';

    case AppThemeStyle.panda:
      final eyes = mood == MascotMood.happy
          ? '<path d="M31.5 47.5C33.8 43.5 38.8 43.5 41 47.5" stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round"/><path d="M63 47.5C65.2 43.5 70.2 43.5 72.5 47.5" stroke="#FFFFFF" stroke-width="2.5" stroke-linecap="round"/>'
          : '<circle cx="38.5" cy="47.5" r="4.2" fill="#FFFFFF"/><circle cx="39.2" cy="47.6" r="3" fill="#232825"/><circle cx="37.6" cy="45.7" r="1.5" fill="#FFFFFF"/><circle cx="40.5" cy="49.3" r="0.8" fill="#FFFFFF"/><circle cx="65.5" cy="47.5" r="4.2" fill="#FFFFFF"/><circle cx="64.8" cy="47.6" r="3" fill="#232825"/><circle cx="66.4" cy="45.7" r="1.5" fill="#FFFFFF"/><circle cx="63.5" cy="49.3" r="0.8" fill="#FFFFFF"/>';
      return '<svg viewBox="0 0 104 92" fill="none" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M88 18C88 15.5 91 14.5 92.4 16.5C93.8 14.5 96.8 15.5 96.8 18C96.8 20.6 92.4 23.4 92.4 23.4C92.4 23.4 88 20.6 88 18Z" fill="#FFAAB6"/>'
          '<circle cx="24" cy="26" r="12" fill="#3C4440"/>'
          '<circle cx="24.5" cy="26.5" r="5.5" fill="#545E58" opacity="0.45"/>'
          '<circle cx="80" cy="26" r="12" fill="#3C4440"/>'
          '<circle cx="79.5" cy="26.5" r="5.5" fill="#545E58" opacity="0.45"/>'
          '<path d="M17 55C17 34 31 20 52 20C73 20 87 34 87 55C87 71 74 79 52 79C30 79 17 71 17 55Z" fill="#FFFFFF" stroke="#3C4440" stroke-width="1.8"/>'
          '<path d="M48 20.5C47 15.5 51 13.5 52.5 17C54 14 57.5 15.5 56 20.5" fill="#FFFFFF" stroke="#3C4440" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>'
          '<path d="M22 65C30 75 74 75 82 65C74 72 30 72 22 65Z" fill="#EDF6F2"/>'
          '<ellipse cx="36" cy="49" rx="10.5" ry="11.5" transform="rotate(20 36 49)" fill="#3C4440"/>'
          '<ellipse cx="68" cy="49" rx="10.5" ry="11.5" transform="rotate(-20 68 49)" fill="#3C4440"/>'
          '$eyes'
          '<ellipse cx="24.5" cy="59.5" rx="6.5" ry="3.8" fill="#FFA8B4" opacity="0.72"/>'
          '<ellipse cx="79.5" cy="59.5" rx="6.5" ry="3.8" fill="#FFA8B4" opacity="0.72"/>'
          '<ellipse cx="52" cy="54.2" rx="4.2" ry="2.7" fill="#3C4440"/>'
          '<path d="M46 59.2C47.8 61.8 50.6 61.5 52 58.6C53.4 61.5 56.2 61.8 58 59.2" stroke="#3C4440" stroke-width="1.9" stroke-linecap="round"/>'
          '<path d="M49.5 61C49.5 64.5 54.5 64.5 54.5 61Z" fill="#FF9CA8"/>'
          '<path d="M24 75C34 83 70 83 80 75" stroke="#3C4440" stroke-width="6.2" stroke-linecap="round"/>'
          '<g transform="translate(46 63) rotate(12)">'
          '<path d="M6 2L12 19H0L6 2Z" fill="#8CD9A8" stroke="#3D8560" stroke-width="1.5" stroke-linejoin="round"/>'
          '<path d="M3 12L9 9.5M2 16L10.5 14" stroke="#52A878" stroke-width="1.3" stroke-linecap="round"/>'
          '<path d="M7 4C11 0 15 1 16 3.5C13 5.5 9.5 5.5 7 4Z" fill="#63C78F"/>'
          '</g>'
          '<ellipse cx="33" cy="79" rx="10.5" ry="7.4" fill="#3C4440"/>'
          '<circle cx="33" cy="79.5" r="2.2" fill="#FFB6C0" opacity="0.88"/>'
          '<circle cx="29.5" cy="76.5" r="1.1" fill="#FFB6C0" opacity="0.88"/><circle cx="33" cy="75.5" r="1.1" fill="#FFB6C0" opacity="0.88"/><circle cx="36.5" cy="76.5" r="1.1" fill="#FFB6C0" opacity="0.88"/>'
          '<ellipse cx="71" cy="79" rx="10.5" ry="7.4" fill="#3C4440"/>'
          '<circle cx="71" cy="79.5" r="2.2" fill="#FFB6C0" opacity="0.88"/>'
          '<circle cx="67.5" cy="76.5" r="1.1" fill="#FFB6C0" opacity="0.88"/><circle cx="71" cy="75.5" r="1.1" fill="#FFB6C0" opacity="0.88"/><circle cx="74.5" cy="76.5" r="1.1" fill="#FFB6C0" opacity="0.88"/>'
          '</svg>';

    case AppThemeStyle.capybara:
      final eyes = mood == MascotMood.curious
          ? '<path d="M31 46.5H42" stroke="#4A2E19" stroke-width="2.4" stroke-linecap="round"/><circle cx="36.5" cy="49" r="2.2" fill="#4A2E19"/><path d="M62 46.5H73" stroke="#4A2E19" stroke-width="2.4" stroke-linecap="round"/><circle cx="67.5" cy="49" r="2.2" fill="#4A2E19"/>'
          : '<path d="M30 48.5C32.5 45.5 39.5 45.5 42 48.5" stroke="#4A2E19" stroke-width="2.5" stroke-linecap="round"/><path d="M62 48.5C64.5 45.5 71.5 45.5 74 48.5" stroke="#4A2E19" stroke-width="2.5" stroke-linecap="round"/>';
      return '<svg viewBox="0 0 104 92" fill="none" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M12 44C9 39 14 35 11 30" stroke="#DFA874" stroke-width="1.8" stroke-linecap="round" opacity="0.75"/>'
          '<path d="M92 42C95 37 90 33 93 28" stroke="#DFA874" stroke-width="1.8" stroke-linecap="round" opacity="0.75"/>'
          '<ellipse cx="52" cy="21" rx="11.5" ry="9.2" fill="#F7AC5B" stroke="#945B24" stroke-width="1.5"/>'
          '<ellipse cx="48" cy="17.5" rx="2.6" ry="1.4" transform="rotate(-22 48 17.5)" fill="#FFEAC0" opacity="0.85"/>'
          '<ellipse cx="52" cy="9.5" rx="6.8" ry="5.5" fill="#FBC46E" stroke="#945B24" stroke-width="1.3"/>'
          '<path d="M52 4.5C54.5 1 59.5 1.5 61 4.5C58 6.5 54.5 6.8 52 4.5Z" fill="#70C478" stroke="#3F8245" stroke-width="1.1"/>'
          '<ellipse cx="24" cy="36" rx="6.5" ry="7.8" transform="rotate(-24 24 36)" fill="#B08460" stroke="#63442A" stroke-width="1.7"/>'
          '<ellipse cx="80" cy="36" rx="6.5" ry="7.8" transform="rotate(24 80 36)" fill="#B08460" stroke="#63442A" stroke-width="1.7"/>'
          '<rect x="17" y="29" width="70" height="48" rx="24" fill="#CA9E76" stroke="#63442A" stroke-width="1.8"/>'
          '<ellipse cx="52" cy="58" rx="22" ry="14.5" fill="#E6C9A8"/>'
          '$eyes'
          '<ellipse cx="27" cy="55.5" rx="5.5" ry="3.2" fill="#FFA28A" opacity="0.58"/>'
          '<ellipse cx="77" cy="55.5" rx="5.5" ry="3.2" fill="#FFA28A" opacity="0.58"/>'
          '<ellipse cx="52" cy="53.5" rx="4.6" ry="2.8" fill="#593A22"/>'
          '<path d="M52 56.2V61.2M52 61.2C49.2 63.4 46.5 63 45.2 61.2M52 61.2C54.8 63.4 57.5 63 58.8 61.2" stroke="#593A22" stroke-width="1.8" stroke-linecap="round"/>'
          '<ellipse cx="29" cy="79" rx="10" ry="6.8" fill="#BD8F68" stroke="#63442A" stroke-width="1.7"/>'
          '<ellipse cx="75" cy="79" rx="10" ry="6.8" fill="#BD8F68" stroke="#63442A" stroke-width="1.7"/>'
          '</svg>';

    case AppThemeStyle.taro:
      final eyes = mood == MascotMood.happy
          ? '<path d="M33 47.5C35.5 43.2 40.5 43.2 43 47.5" stroke="#4B387C" stroke-width="2.5" stroke-linecap="round"/><path d="M61 47.5C63.5 43.2 68.5 43.2 71 47.5" stroke="#4B387C" stroke-width="2.5" stroke-linecap="round"/>'
          : '<ellipse cx="38" cy="47" rx="4.8" ry="5.5" fill="#483680"/><path d="M36.8 43.8L37.4 45.6L39.2 46.2L37.4 46.8L36.8 48.6L36.2 46.8L34.4 46.2L36.2 45.6L36.8 43.8Z" fill="#FFF7C8"/><circle cx="39.5" cy="49.6" r="1" fill="#FFFFFF"/><ellipse cx="66" cy="47" rx="4.8" ry="5.5" fill="#483680"/><path d="M64.8 43.8L65.4 45.6L67.2 46.2L65.4 46.8L64.8 48.6L64.2 46.8L62.4 46.2L64.2 45.6L64.8 43.8Z" fill="#FFF7C8"/><circle cx="67.5" cy="49.6" r="1" fill="#FFFFFF"/>';
      final mouth = mood == MascotMood.curious
          ? '<circle cx="52" cy="55" r="2.2" fill="#F49ECB"/>'
          : '<path d="M47 53.5H57C57 58.2 54.8 60 52 60C49.2 60 47 58.2 47 53.5Z" fill="#F79EC9" stroke="#5E489C" stroke-width="1.4" stroke-linejoin="round"/>';
      return '<svg viewBox="0 0 104 92" fill="none" xmlns="http://www.w3.org/2000/svg">'
          '<path d="M14 18L15.6 22L19.6 23.6L15.6 25.2L14 29.2L12.4 25.2L8.4 23.6L12.4 22L14 18Z" fill="#FFE48A"/>'
          '<circle cx="90" cy="22" r="2.6" fill="#F6B8E2"/>'
          '<g transform="translate(52 8) rotate(12)">'
          '<path d="M1 14L4 3L10 8.5L16 1.5L20 10L25 5L23.5 15Z" fill="#FFE58F" stroke="#B58B2E" stroke-width="1.4" stroke-linejoin="round"/>'
          '<circle cx="15" cy="10" r="1.7" fill="#F096CA"/>'
          '</g>'
          '<path d="M23 70C14 70 10 62 12 54C13.5 47 19 43.5 23.5 43.5C22.5 33 31 24.5 41.5 26C47 19 60 19 65.5 26C76 24.5 84 33 83 43.5C88.5 44.5 93.5 49 93 56C93 65 86 70 78 70H23Z" fill="#FFFFFF" stroke="#856EC9" stroke-width="1.8" stroke-linejoin="round"/>'
          '<path d="M23 66.5H78C83 66.5 87 63.5 88 60C84 63.5 79 64.5 74 64.5H27C22 64.5 17.5 63 16 60C17 64 19.5 66.5 23 66.5Z" fill="#E6DAFC"/>'
          '$eyes'
          '<ellipse cx="28" cy="54" rx="5.5" ry="3.1" fill="#FFB0DC" opacity="0.72"/>'
          '<ellipse cx="76" cy="54" rx="5.5" ry="3.1" fill="#FFB0DC" opacity="0.72"/>'
          '$mouth'
          '<ellipse cx="29" cy="74" rx="9" ry="6" fill="#FFFFFF" stroke="#856EC9" stroke-width="1.7"/>'
          '<ellipse cx="75" cy="74" rx="9" ry="6" fill="#FFFFFF" stroke="#856EC9" stroke-width="1.7"/>'
          '<path d="M81 71L89 58" stroke="#A08AE2" stroke-width="2" stroke-linecap="round"/>'
          '<path d="M90 51L91.8 55.4L96.2 57.2L91.8 59L90 63.4L88.2 59L83.8 57.2L88.2 55.4L90 51Z" fill="#FFE58F" stroke="#B58B2E" stroke-width="1.2"/>'
          '</svg>';

    case AppThemeStyle.matcha:
      final eyes = mood == MascotMood.happy
          ? '<path d="M32 48C34.2 44 39.2 44 41.5 48" stroke="#422612" stroke-width="2.5" stroke-linecap="round"/><path d="M62.5 48C64.8 44 69.8 44 72 48" stroke="#422612" stroke-width="2.5" stroke-linecap="round"/>'
          : '<circle cx="37.5" cy="48" r="4.2" fill="#3B210E"/><circle cx="36.2" cy="46.4" r="1.6" fill="#FFFFFF"/><circle cx="66.5" cy="48" r="4.2" fill="#3B210E"/><circle cx="65.2" cy="46.4" r="1.6" fill="#FFFFFF"/>';
      return '<svg viewBox="0 0 104 92" fill="none" xmlns="http://www.w3.org/2000/svg">'
          '<g transform="translate(84 14)">'
          '<circle cx="6" cy="3.5" r="3" fill="#82CA89"/><circle cx="9.2" cy="6.8" r="3" fill="#68B570"/>'
          '<circle cx="6" cy="10" r="3" fill="#82CA89"/><circle cx="2.8" cy="6.8" r="3" fill="#68B570"/>'
          '</g>'
          '<circle cx="25" cy="32" r="10.5" fill="#C4946A" stroke="#664226" stroke-width="1.7"/>'
          '<circle cx="25" cy="32" r="5" fill="#F0D8BE"/>'
          '<circle cx="79" cy="32" r="10.5" fill="#C4946A" stroke="#664226" stroke-width="1.7"/>'
          '<circle cx="79" cy="32" r="5" fill="#F0D8BE"/>'
          '<path d="M17 53C17 34 32 23 52 23C72 23 87 34 87 53C87 69 74 77 52 77C30 77 17 69 17 53Z" fill="#CC9E75" stroke="#664226" stroke-width="1.8"/>'
          '<path d="M25 30C27 14 45 9 63 13C75 16 82 24 77 32.5C64 26 39 25.5 25 30Z" fill="#83C48A" stroke="#3D7845" stroke-width="1.7" stroke-linejoin="round"/>'
          '<path d="M54 11.5C55 7 58 6 61 7.5" stroke="#3D7845" stroke-width="2.1" stroke-linecap="round"/>'
          '<ellipse cx="52" cy="58.5" rx="16" ry="11.5" fill="#FAF2E6"/>'
          '$eyes'
          '<ellipse cx="27" cy="55.5" rx="5.2" ry="3" fill="#FFA092" opacity="0.58"/>'
          '<ellipse cx="77" cy="55.5" rx="5.2" ry="3" fill="#FFA092" opacity="0.58"/>'
          '<ellipse cx="52" cy="54.2" rx="4.4" ry="3" fill="#54331A"/>'
          '<path d="M52 57.2V60.5M47 60.5C48.6 63 51 62.6 52 60.5C53 62.6 55.4 63 57 60.5" stroke="#54331A" stroke-width="1.8" stroke-linecap="round"/>'
          '<g transform="translate(41 64)">'
          '<rect x="3" y="5" width="16" height="15" rx="4" fill="#FFFFFF" stroke="#528859" stroke-width="1.5"/>'
          '<rect x="5" y="7" width="12" height="5" rx="2" fill="#8CD192"/>'
          '<path d="M19 8.5C22.5 8.5 22.5 14.5 19 14.5" stroke="#528859" stroke-width="1.5" stroke-linecap="round"/>'
          '<path d="M8 2.5C7.5 1 9 0 8.5 -1.5M13.5 2.5C13 1 14.5 0 14 -1.5" stroke="#92CC98" stroke-width="1.3" stroke-linecap="round"/>'
          '</g>'
          '<ellipse cx="36" cy="78" rx="9.5" ry="6.8" fill="#C4946A" stroke="#664226" stroke-width="1.7"/>'
          '<ellipse cx="68" cy="78" rx="9.5" ry="6.8" fill="#C4946A" stroke="#664226" stroke-width="1.7"/>'
          '</svg>';

    case AppThemeStyle.emerald:
    case AppThemeStyle.mono:
    case AppThemeStyle.oat:
      return null;
  }
}
