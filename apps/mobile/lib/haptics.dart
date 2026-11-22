import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'store.dart';

Future<void> keyFeedback(
  LedgerStore store, {
  String? level,
  bool prepare = false,
}) async {
  final strength = level ?? store.state['keyHaptic'] ?? 'light';
  if (strength == 'off') return;
  try {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await system.invokeMethod(
        prepare ? 'prepareKeyHaptic' : 'keyHaptic',
        strength,
      );
      return;
    }
    if (prepare) return;
    switch (strength) {
      case 'strong':
        await HapticFeedback.heavyImpact();
      case 'medium':
        await HapticFeedback.mediumImpact();
      default:
        await HapticFeedback.lightImpact();
    }
  } on MissingPluginException {
    // Unsupported hosts have no physical haptic engine.
  } on PlatformException {
    // Haptic feedback is independent of transaction input and persistence.
  }
}

Future<void> successFeedback(LedgerStore s) async {
  if (s.state['keyHaptic'] == 'off') return;
  try {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await system.invokeMethod('successHaptic');
    } else {
      await HapticFeedback.mediumImpact();
    }
  } on MissingPluginException {
    // Unsupported hosts have no feedback engine.
  } on PlatformException {
    /* Feedback must not block a saved record. */
  }
}
