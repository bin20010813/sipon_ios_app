import 'package:flutter/foundation.dart';

/// The map engine is selected once for both the view and its controller.
enum MapEngine { mapKit, tianditu, unsupported }

MapEngine selectMapEngine({TargetPlatform? platform, bool? isWeb}) {
  if (isWeb ?? kIsWeb) return MapEngine.unsupported;
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return MapEngine.mapKit;
    case TargetPlatform.android:
      return MapEngine.tianditu;
    default:
      return MapEngine.unsupported;
  }
}
