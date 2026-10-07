import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:sipon/features/map/platform/petal_map_platform.dart';
import 'package:sipon/features/map/platform/sipon_map_protocol.dart';
import 'package:sipon/main.dart' as app;

Future<void> main() async {
  PetalMapPlatform.viewBuilder =
      ({
        required key,
        required creationParams,
        required gestureRecognizers,
        required onPlatformViewCreated,
      }) => OhosView(
        key: key,
        viewType: kSiponPetalViewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: gestureRecognizers,
        onPlatformViewCreated: onPlatformViewCreated,
      );
  await app.main();
}
