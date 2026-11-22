import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const defaultFontScale = .95;
double fontScaleOf(Map<String, dynamic> state) {
  final value = state['fontScale'];
  return value is num && value.isFinite
      ? value.toDouble().clamp(.8, 1.4)
      : defaultFontScale;
}

SystemUiOverlayStyle appSystemBars(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: dark
        ? Brightness.light
        : Brightness.dark,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );
}

/// Keep the OS nonlinear accessibility curve only when explicitly requested.
class AppTextScaler extends TextScaler {
  final TextScaler system;
  final double factor;
  const AppTextScaler(this.system, this.factor);
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}

/// Real insets stay intact; only wide windows are constrained, never pixels/DPR.
class AdaptiveDisplay extends StatelessWidget {
  final double scale;
  final bool followSystem;
  final Widget child;
  const AdaptiveDisplay({
    super.key,
    required this.scale,
    required this.followSystem,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final media = MediaQuery.of(context);
      final width = box.maxWidth.clamp(0.0, 720.0);
      final side = (box.maxWidth - width) / 2;
      EdgeInsets adjusted(EdgeInsets inset) => inset.copyWith(
        left: (inset.left - side).clamp(0.0, double.infinity),
        right: (inset.right - side).clamp(0.0, double.infinity),
      );
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: appSystemBars(Theme.of(context).brightness),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: box.maxHeight,
            child: MediaQuery(
              data: media.copyWith(
                size: Size(width, box.maxHeight),
                padding: adjusted(media.padding),
                viewPadding: adjusted(media.viewPadding),
                textScaler: AppTextScaler(
                  followSystem ? media.textScaler : TextScaler.noScaling,
                  scale,
                ),
              ),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

/// Spacing responds to available logical width, not device model or pixel count.
double pageGutter(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * .045).clamp(14.0, 22.0);
