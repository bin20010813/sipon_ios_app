import 'package:flutter/foundation.dart';

/// The map engine is selected once for both the view and its controller.
enum MapEngine { mapKit, tianditu, petal, unsupported }

MapEngine selectMapEngine({TargetPlatform? platform, bool? isWeb}) {
  if (isWeb ?? kIsWeb) return MapEngine.unsupported;
  // The OpenHarmony Flutter SDK adds TargetPlatform.ohos. Using its name
  // keeps the shared application compilable with the upstream Flutter SDK.
  if ((platform ?? defaultTargetPlatform).name == 'ohos') {
    return MapEngine.petal;
  }
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.iOS:
      return MapEngine.mapKit;
    case TargetPlatform.android:
      return MapEngine.tianditu;
    default:
      return MapEngine.unsupported;
  }
}
