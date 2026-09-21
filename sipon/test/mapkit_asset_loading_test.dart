import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/services/map/checkin_pin_icon.dart';
import 'package:sipon/services/map/map_models.dart';
import 'package:sipon/services/map/mapkit_scene_controller.dart';
import 'package:sipon/services/map/sipon_map_host.dart';
import 'package:sipon/services/map/sipon_map_protocol.dart';

class _Host implements SiponMapHost {
  late void Function(String, Object?) handler;
  final calls = <String, Map<String, Object?>>{};

  @override
  void onNativeCall(void Function(String, Object?) handler) {
    this.handler = handler;
  }

  @override
  Future<Object?> invoke(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    calls[method] = args;
    if (method == SiponMapCommands.setup) {
      handler(SiponMapEvents.onMapReady, null);
    }
    return null;
  }
}

class _DelayedBundle extends CachingAssetBundle {
  final pending = Completer<ByteData>();
  @override
  Future<ByteData> load(String key) => pending.future;
}

MapkitSceneController _controller({AssetBundle? bundle}) =>
    MapkitSceneController(
      onViewportSettled: (_) {},
      onVenueTapped: (_) {},
      onBlankTapped: () {},
      assetBundle: bundle,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('五类真实图标与打卡图钉注册到原生，通道传输后仍可解码', () async {
    final host = _Host();
    final controller = _controller();
    addTearDown(controller.detach);
    await controller.attach(host, city: '上海');
    final payload = host.calls[SiponMapCommands.registerAssets]!;
    const codec = StandardMethodCodec();
    final decoded = codec.decodeMethodCall(
      codec.encodeMethodCall(
        MethodCall(SiponMapCommands.registerAssets, payload),
      ),
    );
    final assets = (decoded.arguments as Map)['assets'] as Map;
    expect(
      assets.keys.toSet(),
      {...MapVenueKind.values.map((e) => e.id), checkInPinCategory},
    );
    for (final data in assets.values) {
      expect(data, isA<Uint8List>());
      final imageCodec = await ui.instantiateImageCodec(data as Uint8List);
      final frame = await imageCodec.getNextFrame();
      expect(frame.image.width, greaterThan(0));
      expect(frame.image.height, greaterThan(0));
      frame.image.dispose();
      imageCodec.dispose();
    }
    // 打卡图钉按 3x 出图，原生以 scale=3 解码回 22×28pt。
    final pinCodec = await ui.instantiateImageCodec(
      assets[checkInPinCategory]! as Uint8List,
    );
    final pinFrame = await pinCodec.getNextFrame();
    expect(pinFrame.image.width, 66);
    expect(pinFrame.image.height, 84);
    pinFrame.image.dispose();
    pinCodec.dispose();
  });

  test('资源加载期间销毁地图不再向旧通道注册', () async {
    final bundle = _DelayedBundle();
    final host = _Host();
    final controller = _controller(bundle: bundle);
    final attaching = controller.attach(host, city: '上海');
    await Future<void>.delayed(Duration.zero);
    controller.detach();
    bundle.pending.complete(ByteData(1));
    await attaching;
    expect(host.calls.containsKey(SiponMapCommands.registerAssets), isFalse);
  });
}
