import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../pages/language_transform.dart';
import '../../services/map/map_display_options.dart';
import '../../services/map/map_models.dart';
import '../../services/map/map_scene_controller.dart';
import '../../services/map/map_viewport.dart';
import '../../services/map/sipon_map_host.dart';
import '../../services/map/sipon_map_widget.dart';
import '../../services/sipon_city_controller.dart';

/// 详情页内的展示型地图层：只画一个地点并聚焦到位。
///
/// 刻意不经过地图 Tab 的 [MapPage]：那里带着视野取数、筛选与面板档位状态机，
/// 是地图 Tab 交互链路的专属组件。这里只复用更底层的 [MapSceneController] +
/// [SiponMapWidget] 组装（RouteDetailMapPage 同款），行为完全确定：
/// attach → 下发单点帧 → half 档取景，不做任何取数与选中对账。
///
/// 取景数值抄自 VenueSheetController 的 half 档语义（面板 0.55 屏高、
/// 相机下边距让位 0.43），是对齐的快照而非共享引用：详情页地图层不依赖
/// 地图 Tab 的任何文件，日后 Tab 调参不会自动跟进，需要手动同步。
class VenueMiniMap extends StatefulWidget {
  const VenueMiniMap({
    super.key,
    required this.venue,
    this.onBlankTapped,
    this.centered = false,
  });

  final MapVenue venue;

  /// Center the point inside this map instead of reserving a detail sheet.
  final bool centered;

  /// 点地图空白处（无 marker 命中）时回调，详情页用来收回地图。
  final VoidCallback? onBlankTapped;

  @override
  State<VenueMiniMap> createState() => _VenueMiniMapState();
}

class _VenueMiniMapState extends State<VenueMiniMap> {
  /// half 档取景的数值快照（来源 VenueSheetController 的 halfExtent 0.55 与
  /// cameraPaddingShrink 0.12）：面板占下方 55% 屏高，相机下边距让出 43%。
  static const double _sheetFraction = 0.55;
  static const double _cameraBottomFraction = 0.43;

  late final MapSceneController _scene = MapSceneController.create(
    onViewportSettled: (_) {},
    onVenueTapped: (_) {},
    onBlankTapped: _handleBlankTapped,
  );

  void _handleBlankTapped() => widget.onBlankTapped?.call();

  @override
  void dispose() {
    _scene.detach();
    super.dispose();
  }

  /// 地图宿主就绪：attach（阻塞到原生 onMapReady）→ 下发单点帧 → 取景。
  ///
  /// attach 是异步的，页面可能在等待期间就被收回（点地址后立刻收回），
  /// 所以每个 await 之后都检查 [mounted]，detached 后不再下发任何指令。
  Future<void> _handleHostReady(SiponMapHost host) async {
    final height = MediaQuery.sizeOf(context).height;
    final venue = widget.venue;
    final text = SiponLanguageScope.textOf(context);

    await _scene.attach(
      host,
      city: SiponCityController.defaultCity,
      style: MapBaseStyle.standard,
    );
    if (!mounted) return;

    final point = MapPoint(
      id: 'detail-${venue.id}',
      name: venue.name,
      longitude: venue.longitude,
      latitude: venue.latitude,
      kind: venue.kind,
      weight: venue.rating,
      venueId: venue.id,
    );
    await _scene.render(
      MapSceneFrame(
        circlePoints: [point],
        markers: [
          MapMarkerSpec(
            venueId: venue.id,
            label: text.t(venue.name),
            longitude: venue.longitude,
            latitude: venue.latitude,
            kind: venue.kind,
          ),
        ],
        selected: point,
      ),
    );
    if (!mounted) return;

    // half 档取景：相机下边距让出下半屏，把聚焦点压回上半屏视觉重心，
    // 与 VenueMapHalfPage 呈现的视角一致。
    await _scene.applyStage(
      cameraBottomPadding: widget.centered ? 0 : height * _cameraBottomFraction,
      ornamentBottomMargin: widget.centered ? 8 : height * _sheetFraction + 8,
      focus: MapLatLng(longitude: venue.longitude, latitude: venue.latitude),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Darwin 平台视图只在 iOS 存在：其他平台创建 UiKitView 会抛
    // PlatformException 并把整页拖垮。守卫后显示占位，详情下沉交互
    // 在 Android 调试时依然可用，地图本体等真机 iOS 验证。
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return GestureDetector(
        onTap: _handleBlankTapped,
        child: const ColoredBox(
          color: Color(0xFFF3F0F2),
          child: Center(
            child: Text(
              '地图暂只支持 iOS 设备',
              style: TextStyle(color: Color(0xFF8E8790), fontSize: 13),
            ),
          ),
        ),
      );
    }

    return SiponMapWidget(
      initialStyleId: MapBaseStyle.standard.id,
      onHostReady: _handleHostReady,
    );
  }
}
