import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/route_planner.dart';
import '../models/map_display_options.dart';
import '../models/map_viewport.dart';
import '../platform/sipon_map_host.dart';
import '../platform/sipon_map_protocol.dart';
import '../widgets/checkin_pin_icon.dart';
import 'map_scene_controller.dart';
import 'package:sipon/shared/services/map/map_place_result.dart';

/// Android map scene. The current diagnostic build treats business coordinates
/// as GCJ-02; the native adapter converts them at the Tianditu boundary.
class TiandituSceneController extends MapSceneController {
  TiandituSceneController({
    required super.onViewportSettled,
    required super.onVenueTapped,
    required super.onBlankTapped,
    AssetBundle? assetBundle,
    RoutePlanner? routePlanner,
  }) : _assetBundle = assetBundle ?? rootBundle,
       _routePlanner = routePlanner;

  final AssetBundle _assetBundle;
  final RoutePlanner? _routePlanner;
  SiponMapHost? _host;
  Completer<void>? _readyCompleter;
  Timer? _settleTimer;
  SiponViewportPayload? _settlingViewport;
  bool _ready = false;
  bool _failed = false;
  int _attachment = 0;
  int _styleRevision = 0;
  int _routeRevision = 0;
  MapBaseStyle _style = MapBaseStyle.standard;
  List<List<MapLatLng>>? _routeLegs;
  String? lastMapError;
  @override
  String? routeErrorMessage;

  @override
  bool get isAttached => _ready && _host != null;

  @override
  Future<void> attach(
    SiponMapHost host, {
    required String city,
    MapBaseStyle style = MapBaseStyle.standard,
    MapLatLng? initialCenter,
  }) async {
    detach();
    final attachment = ++_attachment;
    _host = host;
    _failed = false;
    _style = style;
    final ready = Completer<void>();
    _readyCompleter = ready;
    host.onNativeCall(handleNativeEvent);
    try {
      await host.invoke(SiponMapCommands.setup, {
        ...encodeSetup(
          city: city,
          style: _style,
          initialCenter: initialCenter ?? mapCenterForCity(city),
        ),
        'zoom': initialCenter == null
            ? MapSceneController.cityZoom
            : MapSceneController.defaultZoom,
      });
      if (!_isCurrent(host, attachment)) return;
      await host.invoke(SiponMapCommands.setGestures, encodeGestures());
      final assets = await _loadAssets();
      if (!_isCurrent(host, attachment)) return;
      await host.invoke(SiponMapCommands.registerAssets, {'assets': assets});
      if (!_isCurrent(host, attachment)) return;
      await ready.future.timeout(const Duration(seconds: 12));
      if (!_isCurrent(host, attachment)) return;
      _readyCompleter = null;
    } on TimeoutException {
      if (_isCurrent(host, attachment)) {
        lastMapError = '地图初始化超时';
        _failReady();
      }
    } catch (error) {
      if (_isCurrent(host, attachment)) {
        lastMapError = '$error';
        _failReady();
      }
    }
  }

  bool _isCurrent(SiponMapHost host, int attachment) =>
      identical(_host, host) && _attachment == attachment;

  Future<Map<String, Uint8List>> _loadAssets() async {
    final keys = encodeMarkerAssets()['assets']! as Map<String, Object?>;
    final images = <String, Uint8List>{};
    for (final entry in keys.entries) {
      try {
        final data = await _assetBundle.load(entry.value! as String);
        images[entry.key] = Uint8List.sublistView(data);
      } catch (error) {
        debugPrint('SiponMap: failed to load ${entry.key}: $error');
      }
    }
    try {
      images[checkInPinCategory] = await buildCheckInPinImage();
    } catch (error) {
      debugPrint('SiponMap: failed to draw check-in pin: $error');
    }
    return images;
  }

  void _failReady() {
    _ready = false;
    _failed = true;
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) ready.complete();
    _readyCompleter = null;
  }

  @override
  void detach() {
    ++_attachment;
    ++_routeRevision;
    ++_styleRevision;
    _settleTimer?.cancel();
    _settleTimer = null;
    _settlingViewport = null;
    _routeLegs = null;
    _failReady();
    final host = _host;
    _host = null;
    if (host != null) {
      unawaited(host.invoke(SiponMapCommands.dispose).catchError((_) => null));
    }
    detachCommon();
  }

  @override
  void handleNativeEvent(String method, Object? arguments) {
    if (_host == null) return;
    switch (method) {
      case SiponMapEvents.onMapReady:
        if (_ready || _failed) return;
        _ready = true;
        lastMapError = null;
        final ready = _readyCompleter;
        if (ready != null && !ready.isCompleted) ready.complete();
        resetStyleCaches();
        final frame = lastFrame;
        if (frame != null) unawaited(performRender(frame));
      case SiponMapEvents.onMapError:
        final args = arguments is Map ? arguments : const {};
        lastMapError = '${args['message'] ?? args['code'] ?? '地图加载失败'}';
        if (!_ready) _failReady();
      case SiponMapEvents.onStyleLoaded:
        final args = arguments is Map ? arguments : const {};
        final revision = args['revision'];
        if (revision is num && revision.toInt() != _styleRevision) return;
        if (_ready) unawaited(_restoreAfterStyle());
      case SiponMapEvents.onViewportSettled:
        final payload = parseViewportPayload(arguments);
        if (payload == null) return;
        _settlingViewport = payload;
        latestZoom = payload.zoom;
        _settleTimer?.cancel();
        _settleTimer = Timer(MapSceneController.idleDebounce, () {
          final current = _settlingViewport;
          _settlingViewport = null;
          if (current != null && isAttached) {
            onViewportSettled(_toViewport(current));
          }
        });
      case SiponMapEvents.onVenueTapped:
        final venueId = parseVenueTapped(arguments);
        if (venueId != null) onVenueTapped(venueId);
      case SiponMapEvents.onBlankTapped:
        onBlankTapped();
    }
  }

  MapViewport _toViewport(SiponViewportPayload payload) => MapViewport(
    bounds: MapBoundsBox(
      west: payload.west,
      south: payload.south,
      east: payload.east,
      north: payload.north,
    ),
    zoom: payload.zoom,
    screenCenter: payload.center,
  );

  @override
  Future<MapViewport?> readViewport() async {
    final host = _host;
    if (host == null || !_ready) return null;
    try {
      final payload = parseViewportPayload(
        await host.invoke(SiponMapCommands.readViewport),
      );
      return payload == null ? null : _toViewport(payload);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setStyle(MapBaseStyle style) async {
    _style = style;
    final revision = ++_styleRevision;
    final host = _host;
    if (host == null || !_ready) return;
    resetStyleCaches();
    await _invokeIfReady(SiponMapCommands.setStyle, {
      ...encodeStyle(_style.id),
      'revision': revision,
    });
  }

  Future<void> _restoreAfterStyle() async {
    await handleStyleLoaded();
    final legs = _routeLegs;
    if (legs != null && isAttached) {
      await _invokeIfReady(
        SiponMapCommands.setRouteGeometry,
        encodeRouteGeometry(legs, revision: _routeRevision),
      );
    }
  }

  @override
  Future<void> easeForPaddingOnly() =>
      _invokeIfReady(SiponMapCommands.applyStage, {
        'bottomPadding': cameraBottomPadding,
        'ornamentBottomMargin': ornamentBottomMargin,
      });

  @override
  Future<void> performSheetFollow(MapLatLng focus) =>
      _invokeIfReady(SiponMapCommands.applyStage, {
        ...encodeApplyStage(bottomPadding: cameraBottomPadding, focus: focus),
        'ornamentBottomMargin': ornamentBottomMargin,
      });

  @override
  Future<void> focusOn({required double longitude, required double latitude}) =>
      _invokeIfReady(SiponMapCommands.focusOn, {
        ...encodeCameraMove(
          longitude: longitude,
          latitude: latitude,
          zoom: 18.0, // Tianditu's maximum business zoom.
          pitch: MapSceneController.focusPitch,
          bearing: MapSceneController.focusBearing,
          bottomPadding: cameraBottomPadding,
        ),
        'durationMs': MapSceneController.focusDuration.inMilliseconds,
        'ornamentBottomMargin': ornamentBottomMargin,
      });

  @override
  Future<void> centerOnUser({
    required double longitude,
    required double latitude,
  }) {
    // 天地图端尚无原生个人点跟随，退化为按兜底坐标聚焦。
    return focusOn(longitude: longitude, latitude: latitude);
  }

  @override
  Future<List<MapPlaceResult>> searchPlaces(String query) async {
    // Apple Maps 地点搜索仅在 MapKit 引擎可用。
    return const [];
  }

  @override
  Future<void> flyToCity(String city, {required double zoom}) {
    final center = mapCenterForCity(city);
    return _invokeIfReady(SiponMapCommands.flyToCity, {
      ...encodeCameraMove(
        longitude: center.longitude,
        latitude: center.latitude,
        zoom: zoom,
        pitch: MapSceneController.defaultPitch,
        bearing: MapSceneController.defaultBearing,
        bottomPadding: cameraBottomPadding,
      ),
      'durationMs': 780,
      'ornamentBottomMargin': ornamentBottomMargin,
    });
  }

  @override
  Future<void> fitRouteStops(List<MapLatLng> points) =>
      _invokeIfReady(SiponMapCommands.fitRouteStops, encodeRoutePoints(points));

  @override
  Future<bool> planRoute({required List<MapLatLng> points}) async {
    final host = _host;
    routeErrorMessage = null;
    if (host == null || !_ready) {
      routeErrorMessage = '地图尚未准备好，请稍后重试';
      return false;
    }
    if (points.length < 2) {
      routeErrorMessage = '请至少选择两个地点';
      return false;
    }
    final revision = ++_routeRevision;
    try {
      final planner = _routePlanner;
      final List<RouteLeg> legs;
      if (planner != null) {
        legs = await planner.plan(
          points: points,
          requestId:
              'android-$revision-${DateTime.now().microsecondsSinceEpoch}',
        );
      } else {
        final response = await host.invoke(
          SiponMapCommands.planRoadRoute,
          encodeRoutePoints(points),
        );
        if (response is! Map || response['crs'] != 'CGCS2000') {
          throw const FormatException('Unexpected Tianditu route coordinates');
        }
        legs = RoutePlanner.parseLegs(response['legs'], expectedLegs: 1);
      }
      if (!_isRouteCurrent(host, revision)) return false;
      final geometry = [for (final leg in legs) leg.coordinates];
      final result = await host.invoke(
        SiponMapCommands.setRouteGeometry,
        encodeRouteGeometry(geometry, revision: revision),
      );
      if (!_isRouteCurrent(host, revision)) return false;
      if (result != true) {
        routeErrorMessage = '地图绘制路线失败，请重试';
        clearRoute();
        return false;
      }
      _routeLegs = geometry;
      return true;
    } catch (error) {
      debugPrint('SiponMap: Android road route failed: $error');
      if (_isRouteCurrent(host, revision)) {
        routeErrorMessage = _describeRouteError(error);
        clearRoute();
      }
      return false;
    }
  }

  String _describeRouteError(Object error) {
    final message = error is PlatformException ? error.message ?? '' : '$error';
    if (message.contains('TDT_ROUTE_KEY is missing')) {
      return '未配置天地图 Key（TDT_KEY 或 TDT_ROUTE_KEY）';
    }
    if (message.contains('301012')) {
      return '天地图 Key 权限类型错误，请配置可调用路线服务的 Key';
    }
    if (message.contains('301018')) {
      return '天地图路线接口不支持当前 Key 类型（301018），请在天地图控制台核对驾车规划 Web 服务的 Key 类型';
    }
    if (message.contains('301020')) {
      return '天地图路线服务安全密钥错误，请检查 TDT_SK 或 TDT_ROUTE_SK';
    }
    if (message.contains('301001') ||
        message.contains('HTTP 401') ||
        message.contains('HTTP 403')) {
      return '天地图路线服务鉴权失败，请检查路线 Key 和服务权限';
    }
    if (message.contains('timeout') || message.contains('timed out')) {
      return '天地图路线请求超时，请稍后重试';
    }
    if (error is FormatException || message.contains('Invalid driving')) {
      return '天地图路线数据格式异常，请稍后重试';
    }
    return '天地图路线请求失败，请检查网络或稍后重试';
  }

  bool _isRouteCurrent(SiponMapHost host, int revision) =>
      identical(_host, host) && _ready && _routeRevision == revision;

  @override
  void clearRoute() {
    ++_routeRevision;
    _routeLegs = null;
    unawaited(_invokeIfReady(SiponMapCommands.clearRoute));
  }

  @override
  Future<void> performRender(MapSceneFrame frame) => _invokeIfReady(
    SiponMapCommands.renderFrame,
    encodeRenderFrame(frame, zoom: latestZoom),
  );

  Future<void> _invokeIfReady(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    final host = _host;
    if (host == null || !_ready) return;
    try {
      await host.invoke(method, args);
    } catch (error) {
      debugPrint('SiponMap: $method failed: $error');
    }
  }
}
