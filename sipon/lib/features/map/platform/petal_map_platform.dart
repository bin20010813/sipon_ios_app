import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

typedef PetalMapViewBuilder =
    Widget Function({
      required Key key,
      required Map<String, Object?> creationParams,
      required Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers,
      required ValueChanged<int> onPlatformViewCreated,
    });

/// Installed by the HarmonyOS entrypoint, which is compiled with Flutter OH.
/// Keeps OhosView references out of the iOS/Android compilation units.
abstract final class PetalMapPlatform {
  static PetalMapViewBuilder? viewBuilder;
}
