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

/// Android map scene. Business coordinates remain WGS-84 at this boundary.
class TiandituSceneController extends MapSceneController {
  TiandituSceneController({
    required super.onViewportSettled,
    required super.onVenueTapped,
    required super.onBlankTapped,
    AssetBundle? assetBundle,
    RoutePlanner? routePlanner,
  }) : _assetBundle = assetBundle ?? rootBundle,
       _routePlanner = routePlanner ?? RoutePlanner();

  final AssetBundle _assetBundle;
  final RoutePlanner _routePlanner;
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
          zoom: MapSceneController.focusZoom,
          pitch: MapSceneController.focusPitch,
          bearing: MapSceneController.focusBearing,
          bottomPadding: cameraBottomPadding,
        ),
        'durationMs': MapSceneController.focusDuration.inMilliseconds,
        'ornamentBottomMargin': ornamentBottomMargin,
      });

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
  Future<bool> planRoute({required List<MapLatLng> points}) async {
    final host = _host;
    if (host == null || !_ready || points.length < 2) return false;
    final revision = ++_routeRevision;
    try {
      final legs = await _routePlanner.plan(
        points: points,
        requestId: 'android-$revision-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (!_isRouteCurrent(host, revision)) return false;
      final geometry = [for (final leg in legs) leg.coordinates];
      final result = await host.invoke(
        SiponMapCommands.setRouteGeometry,
        encodeRouteGeometry(geometry, revision: revision),
      );
      if (!_isRouteCurrent(host, revision)) return false;
      if (result != true) {
        clearRoute();
        return false;
      }
      _routeLegs = geometry;
      return true;
    } catch (error) {
      debugPrint('SiponMap: Android road route failed: $error');
      if (_isRouteCurrent(host, revision)) clearRoute();
      return false;
    }
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
