import 'dart:convert';

import 'package:flutter/material.dart' hide Visibility;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../services/sipon_api_models.dart';
import '../services/sipon_data_repository.dart';
import 'language_transform.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key, this.bottomOverlayInset = 0});

  final double bottomOverlayInset;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const int _maxMarkerAnnotations = 180;
  static const String _geoJsonSourceId = 'sipon_geojson_points_source';
  static const String _heatmapSourceId = 'sipon_heatmap_points_source';
  static const String _geoJsonCircleLayerId = 'sipon_geojson_points_circle';
  static const String _heatmapLayerId = 'sipon_points_heatmap';

  MapboxMap? _mapboxMap;
  PointAnnotationManager? _markerManager;
  Cancelable? _markerTapCancelable;

  static const String _mapTapInteractionId = 'sipon_map_tap_interaction';

  final SiponDataRepository _repository = SiponDataRepository.instance;

  MapboxStyle _currentStyle = MapboxStyle.light;
  MapLayerMode _layerMode = MapLayerMode.pointsAndHeatmap;
  MapLoadingState _loadingState = MapLoadingState.waiting;

  bool _markersLoaded = false;
  bool _geoJsonLoaded = false;
  bool _heatmapLoaded = false;
  int _selectedCategoryIndex = 0;
  List<MapVenue> _venues = _fallbackFeaturedVenues;
  List<MapPoint> _markerPlaces = _buildMarkerPoints(_fallbackFeaturedVenues);
  List<MapPoint> _geoJsonPoints = _buildGeoJsonPoints(_fallbackFeaturedVenues);
  List<MapPoint> _heatmapPoints = _buildHeatmapPoints(
    _buildGeoJsonPoints(_fallbackFeaturedVenues),
  );
  MapVenue _selectedVenue = _fallbackFeaturedVenues.first;
  String? _selectedPointName;
  String? _statusMessage;

  @override
  void dispose() {
    _markerTapCancelable?.cancel();
    _mapboxMap?.removeInteraction(_mapTapInteractionId);
    _markerManager = null;
    _mapboxMap = null;
    super.dispose();
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    await _configureMap(mapboxMap);
    mapboxMap.addInteraction(
      TapInteraction.onMap(_handleMapTap),
      interactionID: _mapTapInteractionId,
    );
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) {
      return;
    }

    await _loadMapData(mapboxMap);
  }

  Future<void> _configureMap(MapboxMap mapboxMap) async {
    await mapboxMap.setCamera(_initialCamera);
    await mapboxMap.compass.updateSettings(
      CompassSettings(
        enabled: false,
        position: OrnamentPosition.TOP_RIGHT,
        marginTop: 20,
        marginRight: 16,
      ),
    );
    await mapboxMap.scaleBar.updateSettings(
      ScaleBarSettings(
        enabled: true,
        position: OrnamentPosition.BOTTOM_LEFT,
        marginLeft: 16,
        marginBottom: 250 + widget.bottomOverlayInset,
      ),
    );
    await mapboxMap.logo.updateSettings(
      LogoSettings(
        position: OrnamentPosition.BOTTOM_LEFT,
        marginLeft: 16,
        marginBottom: 206 + widget.bottomOverlayInset,
      ),
    );
    await mapboxMap.attribution.updateSettings(
      AttributionSettings(
        position: OrnamentPosition.BOTTOM_RIGHT,
        marginRight: 16,
        marginBottom: 206 + widget.bottomOverlayInset,
      ),
    );
    await mapboxMap.gestures.updateSettings(
      GesturesSettings(
        rotateEnabled: true,
        pinchToZoomEnabled: true,
        scrollEnabled: true,
      ),
    );
  }

  Future<void> _loadMapData(MapboxMap mapboxMap) async {
    setState(() {
      _loadingState = MapLoadingState.loading;
      _markersLoaded = false;
      _geoJsonLoaded = false;
      _heatmapLoaded = false;
      _statusMessage = null;
    });

    try {
      final previousMarkerManager = _markerManager;
      _markerTapCancelable?.cancel();
      _markerTapCancelable = null;
      _markerManager = null;

      if (previousMarkerManager != null) {
        try {
          await mapboxMap.annotations.removeAnnotationManager(
            previousMarkerManager,
          );
        } catch (_) {
          // The native style reload can invalidate the old manager before Dart sees it.
        }
      }

      String? statusMessage;
      try {
        final apiVenues = await _fetchVisibleVenues(mapboxMap);
        if (apiVenues.isEmpty) {
          _replaceMapData(_fallbackFeaturedVenues);
          statusMessage = '使用本地示例数据: 接口未返回可展示酒吧';
        } else {
          _replaceMapData(apiVenues);
        }
      } catch (error) {
        _replaceMapData(_fallbackFeaturedVenues);
        statusMessage = '使用本地示例数据: $error';
      }

      await _addMarkerAnnotations(mapboxMap);
      await _addGeoJsonPointLayer(mapboxMap);
      await _addHeatmapLayer(mapboxMap);
      await _applyLayerMode();

      if (!mounted) {
        return;
      }

      setState(() {
        _loadingState = MapLoadingState.loaded;
        _markersLoaded = true;
        _geoJsonLoaded = true;
        _heatmapLoaded = true;
        _statusMessage = statusMessage;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingState = MapLoadingState.failed;
        _statusMessage = '地图数据加载失败: $error';
      });
    }
  }

  Future<List<MapVenue>> _fetchVisibleVenues(MapboxMap mapboxMap) async {
    final cameraState = await mapboxMap.getCameraState();
    final bounds = await mapboxMap.coordinateBoundsForCamera(
      cameraState.toCameraOptions(),
    );
    final apiBounds = bounds.infiniteBounds
        ? const SiponMapBounds.china()
        : SiponMapBounds(
            west: bounds.southwest.coordinates.lng.toDouble(),
            south: bounds.southwest.coordinates.lat.toDouble(),
            east: bounds.northeast.coordinates.lng.toDouble(),
            north: bounds.northeast.coordinates.lat.toDouble(),
          );
    final bars = await _repository.fetchMapBars(
      bounds: apiBounds,
      zoom: cameraState.zoom,
    );

    return [
      for (var index = 0; index < bars.length; index++)
        _venueFromApi(bars[index], index),
    ];
  }

  void _replaceMapData(List<MapVenue> venues) {
    _venues = venues;
    _markerPlaces = _buildMarkerPoints(venues);
    _geoJsonPoints = _buildGeoJsonPoints(venues);
    _heatmapPoints = _buildHeatmapPoints(_geoJsonPoints);
    _selectedVenue = venues.firstWhere(
      (venue) => venue.id == _selectedVenue.id,
      orElse: () => venues.first,
    );
  }

  Future<void> _addMarkerAnnotations(MapboxMap mapboxMap) async {
    final text = SiponLanguageScope.textOf(context);
    final manager = await mapboxMap.annotations.createPointAnnotationManager(
      id: 'sipon_marker_annotations',
    );
    _markerManager = manager;

    await manager.setIconAllowOverlap(true);
    await manager.setTextAllowOverlap(false);

    final markerOptions = _markerPlaces
        .map(
          (place) => PointAnnotationOptions(
            geometry: place.point,
            iconImage: 'marker-15',
            iconSize: 1.35,
            iconAnchor: IconAnchor.BOTTOM,
            textField: text.t(place.name),
            textSize: 12,
            textOffset: const [0, 1.15],
            textAnchor: TextAnchor.TOP,
            textColor: const Color(0xFF0F172A).toARGB32(),
            textHaloColor: Colors.white.toARGB32(),
            textHaloWidth: 1.5,
            customData: {
              'id': place.id,
              'name': place.name,
              'kind': place.kind,
            },
          ),
        )
        .toList();

    await manager.createMulti(markerOptions);
    _markerTapCancelable = manager.tapEvents(
      onTap: (annotation) {
        final name = annotation.customData?['name']?.toString();
        if (mounted && name != null) {
          final matchingVenue = _venueByName(name);
          setState(() {
            _selectedPointName = name;
            if (matchingVenue != null) {
              _selectedVenue = matchingVenue;
            }
          });
        }
      },
    );
  }

  MapVenue? _venueByName(String name) {
    for (final venue in _venues) {
      if (venue.name == name) {
        return venue;
      }
    }

    return null;
  }

  Future<void> _addGeoJsonPointLayer(MapboxMap mapboxMap) async {
    final source = GeoJsonSource(
      id: _geoJsonSourceId,
      data: _buildFeatureCollection(_geoJsonPoints),
      generateId: true,
    );

    await mapboxMap.style.addSource(source);
    await mapboxMap.style.addLayer(
      CircleLayer(
        id: _geoJsonCircleLayerId,
        sourceId: _geoJsonSourceId,
        slot: LayerSlot.TOP,
        circleColorExpression: [
          'match',
          ['get', 'category'],
          'pub',
          ['rgba', 154, 61, 120, 0.9],
          'craft',
          ['rgba', 13, 148, 136, 0.9],
          'bistro',
          ['rgba', 37, 99, 235, 0.9],
          'party',
          ['rgba', 220, 38, 38, 0.9],
          'livehouse',
          ['rgba', 245, 158, 11, 0.9],
          ['rgba', 71, 85, 105, 0.88],
        ],
        circleRadiusExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          9,
          4,
          13,
          7,
          16,
          11,
        ],
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 1.5,
        circleOpacity: 0.92,
        circleEmissiveStrength: 0.4,
      ),
    );
  }

  Future<void> _addHeatmapLayer(MapboxMap mapboxMap) async {
    final source = GeoJsonSource(
      id: _heatmapSourceId,
      data: _buildFeatureCollection(_heatmapPoints),
      generateId: true,
    );

    await mapboxMap.style.addSource(source);
    await mapboxMap.style.addLayer(
      HeatmapLayer(
        id: _heatmapLayerId,
        sourceId: _heatmapSourceId,
        slot: LayerSlot.MIDDLE,
        maxZoom: 16,
        heatmapWeightExpression: [
          'interpolate',
          ['linear'],
          ['get', 'weight'],
          0,
          0,
          8,
          1,
        ],
        heatmapIntensityExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          9,
          0.7,
          14,
          1.6,
        ],
        heatmapRadiusExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          9,
          16,
          14,
          34,
          16,
          46,
        ],
        heatmapOpacityExpression: [
          'interpolate',
          ['linear'],
          ['zoom'],
          10,
          0.88,
          15,
          0.45,
        ],
        heatmapColorExpression: const [
          'interpolate',
          ['linear'],
          ['heatmap-density'],
          0,
          'rgba(33,102,172,0)',
          0.2,
          'rgb(103,169,207)',
          0.4,
          'rgb(209,229,240)',
          0.6,
          'rgb(253,219,199)',
          0.8,
          'rgb(239,138,98)',
          1,
          'rgb(178,24,43)',
        ],
      ),
    );
  }

  Future<void> _applyLayerMode() async {
    final style = _mapboxMap?.style;
    if (style == null) {
      return;
    }

    await _setLayerVisible(
      _geoJsonCircleLayerId,
      _layerMode == MapLayerMode.pointsOnly ||
          _layerMode == MapLayerMode.pointsAndHeatmap,
    );
    await _setLayerVisible(
      _heatmapLayerId,
      _layerMode == MapLayerMode.heatmapOnly ||
          _layerMode == MapLayerMode.pointsAndHeatmap,
    );
  }

  Future<void> _setLayerVisible(String layerId, bool visible) async {
    final style = _mapboxMap?.style;
    if (style == null || !await style.styleLayerExists(layerId)) {
      return;
    }

    await style.setStyleLayerProperty(
      layerId,
      'visibility',
      visible ? 'visible' : 'none',
    );
  }

  Future<void> _switchStyle(MapboxStyle style) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null || style == _currentStyle) {
      return;
    }

    setState(() {
      _currentStyle = style;
      _loadingState = MapLoadingState.loading;
      _selectedPointName = null;
    });

    await mapboxMap.style.setStyleURI(style.uri);
  }

  Future<void> _switchLayerMode(MapLayerMode mode) async {
    setState(() => _layerMode = mode);
    await _applyLayerMode();
  }

  Future<void> _resetCamera() async {
    await _mapboxMap?.flyTo(
      _overviewCamera,
      MapAnimationOptions(duration: 700),
    );
  }

  Future<void> _focusDowntown() async {
    await _mapboxMap?.flyTo(
      CameraOptions(
        center: _point(121.4702, 31.2227),
        zoom: 15.1,
        pitch: 28,
        bearing: -20,
      ),
      MapAnimationOptions(duration: 800),
    );
  }

  Future<void> _focusVenue(MapVenue venue) async {
    await _mapboxMap?.flyTo(
      CameraOptions(
        center: _point(venue.longitude, venue.latitude),
        zoom: 15.4,
        pitch: 30,
        bearing: -18,
      ),
      MapAnimationOptions(duration: 650),
    );
  }

  void _selectCategory(int index) {
    setState(() => _selectedCategoryIndex = index);
  }

  Future<void> _showMapTools() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _MapToolsSheet(
          currentStyle: _currentStyle,
          currentLayerMode: _layerMode,
          markersLoaded: _markersLoaded,
          geoJsonLoaded: _geoJsonLoaded,
          heatmapLoaded: _heatmapLoaded,
          selectedPointName: _selectedPointName,
          statusMessage: _statusMessage,
          onStyleChanged: _switchStyle,
          onLayerModeChanged: _switchLayerMode,
          onResetCamera: _resetCamera,
          onFocusDowntown: _focusDowntown,
        );
      },
    );
  }

  void _handleMapTap(MapContentGestureContext context) {
    final point = context.point.coordinates;
    setState(() {
      _selectedPointName =
          'Lng ${point.lng.toStringAsFixed(5)}, Lat ${point.lat.toStringAsFixed(5)}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            key: const ValueKey('sipon_map_widget'),
            styleUri: _currentStyle.uri,
            viewport: CameraViewportState(
              center: _initialCenter,
              zoom: 11.6,
              pitch: 24,
              bearing: -12,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: _MapSearchAndFilters(
                selectedCategoryIndex: _selectedCategoryIndex,
                loadingState: _loadingState,
                statusMessage: _statusMessage,
                onCategorySelected: _selectCategory,
                onFilterPressed: _showMapTools,
              ),
            ),
          ),
          Positioned(
            right: 18,
            bottom: widget.bottomOverlayInset + 156,
            child: _MapLocateButton(onPressed: _focusDowntown),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _SelectedVenueCard(
              venue: _selectedVenue,
              bottomOverlayInset: widget.bottomOverlayInset,
              selectedPointName: _selectedPointName,
              onTap: () => _focusVenue(_selectedVenue),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapSearchAndFilters extends StatelessWidget {
  const _MapSearchAndFilters({
    required this.selectedCategoryIndex,
    required this.loadingState,
    required this.statusMessage,
    required this.onCategorySelected,
    required this.onFilterPressed,
  });

  final int selectedCategoryIndex;
  final MapLoadingState loadingState;
  final String? statusMessage;
  final ValueChanged<int> onCategorySelected;
  final VoidCallback onFilterPressed;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 10, 26, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(8),
              elevation: 0,
              child: InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            text.t('搜索喜欢的酒或者酒吧...'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFA9A2A8),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.search_rounded,
                          color: Color(0xFF9A9198),
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: [
                  for (
                    var index = 0;
                    index < _mapCategoryFilters.length;
                    index++
                  )
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _MapCategoryPill(
                        category: _mapCategoryFilters[index],
                        selected: selectedCategoryIndex == index,
                        onTap: () => onCategorySelected(index),
                      ),
                    ),
                  _FilterIconPill(onPressed: onFilterPressed),
                ],
              ),
            ),
            if (loadingState == MapLoadingState.loading ||
                statusMessage != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: Text(
                      text.t(statusMessage ?? loadingState.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: statusMessage == null
                            ? _MapDesign.muted
                            : const Color(0xFFB91C1C),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MapCategoryPill extends StatelessWidget {
  const _MapCategoryPill({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final MapCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Material(
      color: selected ? _MapDesign.brand : Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 13, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (category.iconAsset != null) ...[
                Image.asset(
                  category.iconAsset!,
                  width: 18,
                  height: 18,
                  color: selected ? Colors.white : _MapDesign.brand,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                text.t(category.label),
                style: TextStyle(
                  color: selected ? Colors.white : _MapDesign.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterIconPill extends StatelessWidget {
  const _FilterIconPill({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 42,
          height: 36,
          child: Center(
            child: Image.asset(
              _MapAssets.filter,
              width: 20,
              height: 20,
              color: _MapDesign.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _MapLocateButton extends StatelessWidget {
  const _MapLocateButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 0,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: const SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.my_location_rounded,
            color: Color(0xFF737176),
            size: 25,
          ),
        ),
      ),
    );
  }
}

class _SelectedVenueCard extends StatelessWidget {
  const _SelectedVenueCard({
    required this.venue,
    required this.bottomOverlayInset,
    required this.selectedPointName,
    required this.onTap,
  });

  final MapVenue venue;
  final double bottomOverlayInset;
  final String? selectedPointName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return SafeArea(
      minimum: EdgeInsets.fromLTRB(14, 0, 14, bottomOverlayInset + 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD2D0D2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _VenueImage(
                          imageUrl: venue.imageUrl,
                          assetPath: venue.imageAsset,
                          width: 90,
                          height: 102,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              text.t(venue.name),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _MapDesign.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                Text(
                                  venue.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: _MapDesign.ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                const Icon(
                                  Icons.star_rounded,
                                  color: _MapDesign.brand,
                                  size: 15,
                                ),
                                const SizedBox(width: 8),
                                for (final tag in venue.tags.take(2)) ...[
                                  _VenueTag(label: text.t(tag)),
                                  const SizedBox(width: 6),
                                ],
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  color: _MapDesign.brand,
                                  size: 17,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    text.t(venue.address),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _MapDesign.muted,
                                      fontSize: 12,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              text.t(venue.distance),
                              style: const TextStyle(
                                color: _MapDesign.muted,
                                fontSize: 12,
                                letterSpacing: 0,
                              ),
                            ),
                            if (selectedPointName != null &&
                                selectedPointName != venue.name) ...[
                              const SizedBox(height: 5),
                              Text(
                                text.t(selectedPointName!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFB7B0B6),
                                  fontSize: 10,
                                  letterSpacing: 0,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VenueImage extends StatelessWidget {
  const _VenueImage({
    required this.imageUrl,
    required this.assetPath,
    required this.width,
    required this.height,
  });

  final String? imageUrl;
  final String assetPath;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _assetImage(),
      );
    }

    return _assetImage();
  }

  Widget _assetImage() {
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: BoxFit.cover,
    );
  }
}

class _VenueTag extends StatelessWidget {
  const _VenueTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFE8F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          label,
          style: const TextStyle(
            color: _MapDesign.brand,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _MapToolsSheet extends StatelessWidget {
  const _MapToolsSheet({
    required this.currentStyle,
    required this.currentLayerMode,
    required this.markersLoaded,
    required this.geoJsonLoaded,
    required this.heatmapLoaded,
    required this.selectedPointName,
    required this.statusMessage,
    required this.onStyleChanged,
    required this.onLayerModeChanged,
    required this.onResetCamera,
    required this.onFocusDowntown,
  });

  final MapboxStyle currentStyle;
  final MapLayerMode currentLayerMode;
  final bool markersLoaded;
  final bool geoJsonLoaded;
  final bool heatmapLoaded;
  final String? selectedPointName;
  final String? statusMessage;
  final ValueChanged<MapboxStyle> onStyleChanged;
  final ValueChanged<MapLayerMode> onLayerModeChanged;
  final VoidCallback onResetCamera;
  final VoidCallback onFocusDowntown;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text.t('地图工具'),
            style: const TextStyle(
              color: _MapDesign.ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          _ToolSection(
            title: text.t('地图样式'),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in MapboxStyle.values)
                  _StyleOption(
                    label: text.t(style.label),
                    selected: style == currentStyle,
                    onTap: () => onStyleChanged(style),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _ToolSection(
            title: text.t('数据图层'),
            child: SegmentedButton<MapLayerMode>(
              segments: MapLayerMode.values
                  .map(
                    (mode) => ButtonSegment<MapLayerMode>(
                      value: mode,
                      icon: Icon(mode.icon),
                      label: Text(text.t(mode.label)),
                    ),
                  )
                  .toList(),
              selected: {currentLayerMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  onLayerModeChanged(selection.first),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LayerStatusChip(
                label: 'marker',
                loaded: markersLoaded,
                color: _MapDesign.brand,
              ),
              _LayerStatusChip(
                label: 'geojson',
                loaded: geoJsonLoaded,
                color: const Color(0xFF10B981),
              ),
              _LayerStatusChip(
                label: 'heatmap',
                loaded: heatmapLoaded,
                color: const Color(0xFFDC2626),
              ),
            ],
          ),
          if (selectedPointName != null || statusMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              text.t(statusMessage ?? selectedPointName!),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: statusMessage == null
                    ? _MapDesign.muted
                    : const Color(0xFFB91C1C),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _ToolActionButton(
                  label: text.t('回到总览'),
                  icon: Icons.my_location_outlined,
                  onTap: onResetCamera,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ToolActionButton(
                  label: text.t('聚焦城区'),
                  icon: Icons.center_focus_strong_outlined,
                  onTap: onFocusDowntown,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToolSection extends StatelessWidget {
  const _ToolSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _MapDesign.ink,
            fontSize: 14,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _StyleOption extends StatelessWidget {
  const _StyleOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: _MapDesign.brand,
      labelStyle: TextStyle(
        color: selected ? Colors.white : _MapDesign.ink,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      side: BorderSide(
        color: selected ? _MapDesign.brand : const Color(0xFFECE6EA),
      ),
    );
  }
}

class _ToolActionButton extends StatelessWidget {
  const _ToolActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFFFFEDF7),
        foregroundColor: _MapDesign.brand,
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _LayerStatusChip extends StatelessWidget {
  const _LayerStatusChip({
    required this.label,
    required this.loaded,
    required this.color,
  });

  final String label;
  final bool loaded;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: loaded ? color.withValues(alpha: 0.11) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: loaded
              ? color.withValues(alpha: 0.26)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            loaded ? Icons.check_circle : Icons.pending_outlined,
            size: 15,
            color: loaded ? color : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: loaded ? const Color(0xFF0F172A) : const Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

enum MapLoadingState {
  waiting('等待地图'),
  loading('正在加载 marker、GeoJSON 与热力图'),
  loaded('地图数据已加载'),
  failed('地图数据加载失败');

  const MapLoadingState(this.label);

  final String label;
}

enum MapboxStyle {
  light('浅色', MapboxStyles.LIGHT),
  standard('标准', MapboxStyles.STANDARD),
  streets('街道', MapboxStyles.MAPBOX_STREETS),
  satellite('卫星', MapboxStyles.SATELLITE_STREETS),
  dark('暗色', MapboxStyles.DARK);

  const MapboxStyle(this.label, this.uri);

  final String label;
  final String uri;
}

enum MapLayerMode {
  pointsAndHeatmap('全部', Icons.layers_outlined),
  pointsOnly('点位', Icons.scatter_plot_outlined),
  heatmapOnly('热力', Icons.local_fire_department_outlined);

  const MapLayerMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _MapDesign {
  const _MapDesign._();

  static const Color brand = Color(0xFF9A3D78);
  static const Color ink = Color(0xFF252229);
  static const Color muted = Color(0xFF9B939B);
}

class _MapAssets {
  const _MapAssets._();

  static const String pub = 'assest/地图/清吧 默认@3x.png';
  static const String livehouse = 'assest/地图/Livehouse 默认@3x.png';
  static const String craft = 'assest/地图/精酿 默认@3x.png';
  static const String bistro = 'assest/地图/Bistro 默认@3x.png';
  static const String party = 'assest/地图/派对 默认@3x.png';
  static const String filter = 'assest/地图/筛选 默认@3x.png';
  static const String barImage = 'assest/首页/图片素材/庙前冰室.png';
  static const String speakLowImage = 'assest/首页/图片素材/Speak Low（彼楼）.png';
  static const String janesImage = 'assest/首页/图片素材/酒吧 Janes and Hooch.png';
  static const String playHouseImage = 'assest/首页/图片素材/Play House 电音夜店.png';
}

class MapCategory {
  const MapCategory({required this.label, this.iconAsset});

  final String label;
  final String? iconAsset;
}

class MapVenue {
  const MapVenue({
    required this.id,
    required this.name,
    required this.longitude,
    required this.latitude,
    required this.kind,
    required this.rating,
    required this.address,
    required this.distance,
    required this.tags,
    required this.iconAsset,
    required this.imageAsset,
    this.imageUrl,
  });

  final String id;
  final String name;
  final double longitude;
  final double latitude;
  final String kind;
  final double rating;
  final String address;
  final String distance;
  final List<String> tags;
  final String iconAsset;
  final String imageAsset;
  final String? imageUrl;

  MapPoint toMapPoint({required String idPrefix, double weightBoost = 0}) {
    return MapPoint(
      id: '$idPrefix-$id',
      name: name,
      longitude: longitude,
      latitude: latitude,
      kind: kind,
      weight: rating + weightBoost,
    );
  }
}

class MapPoint {
  const MapPoint({
    required this.id,
    required this.name,
    required this.longitude,
    required this.latitude,
    required this.kind,
    required this.weight,
  });

  final String id;
  final String name;
  final double longitude;
  final double latitude;
  final String kind;
  final double weight;

  Point get point => _point(longitude, latitude);

  Map<String, dynamic> toFeature() {
    return {
      'type': 'Feature',
      'properties': {
        'id': id,
        'name': name,
        'category': kind,
        'weight': weight,
      },
      'geometry': {
        'type': 'Point',
        'coordinates': [longitude, latitude],
      },
    };
  }
}

CameraOptions get _initialCamera =>
    CameraOptions(center: _initialCenter, zoom: 15.05, pitch: 24, bearing: -12);

CameraOptions get _overviewCamera =>
    CameraOptions(center: _initialCenter, zoom: 15.05, pitch: 24, bearing: -12);

Point get _initialCenter => _point(121.4712, 31.2227);

Point _point(double longitude, double latitude) {
  return Point(coordinates: Position(longitude, latitude));
}

String _buildFeatureCollection(List<MapPoint> points) {
  return jsonEncode({
    'type': 'FeatureCollection',
    'features': points.map((point) => point.toFeature()).toList(),
  });
}

const List<MapCategory> _mapCategoryFilters = [
  MapCategory(label: '清吧', iconAsset: _MapAssets.pub),
  MapCategory(label: 'Livehouse', iconAsset: _MapAssets.livehouse),
  MapCategory(label: '精酿', iconAsset: _MapAssets.craft),
  MapCategory(label: 'Bistro', iconAsset: _MapAssets.bistro),
  MapCategory(label: '派对', iconAsset: _MapAssets.party),
];

MapVenue _venueFromApi(SiponBarMapItem item, int index) {
  return MapVenue(
    id: item.id,
    name: item.name,
    longitude: item.longitude!,
    latitude: item.latitude!,
    kind: item.kind,
    rating: item.rating,
    address: item.address,
    distance: item.distance,
    tags: item.tags,
    iconAsset: _iconAssetForKind(item.kind),
    imageAsset: _imageAssetForIndex(index),
    imageUrl: item.imageUrl,
  );
}

String _iconAssetForKind(String kind) {
  return switch (kind) {
    'craft' => _MapAssets.craft,
    'bistro' => _MapAssets.bistro,
    'party' => _MapAssets.party,
    'livehouse' => _MapAssets.livehouse,
    _ => _MapAssets.pub,
  };
}

String _imageAssetForIndex(int index) {
  const images = [
    _MapAssets.barImage,
    _MapAssets.speakLowImage,
    _MapAssets.janesImage,
    _MapAssets.playHouseImage,
  ];

  return images[index % images.length];
}

List<MapPoint> _buildMarkerPoints(List<MapVenue> venues) {
  return _sampleVenuesForMarkerAnnotations(venues)
      .map((venue) => venue.toMapPoint(idPrefix: 'marker'))
      .toList(growable: false);
}

List<MapVenue> _sampleVenuesForMarkerAnnotations(List<MapVenue> venues) {
  const markerLimit = _MapPageState._maxMarkerAnnotations;
  if (venues.length <= markerLimit) {
    return venues;
  }

  final step = venues.length / markerLimit;

  return [
    for (var index = 0; index < markerLimit; index++)
      venues[(index * step).floor()],
  ];
}

List<MapPoint> _buildGeoJsonPoints(List<MapVenue> venues) {
  return [
    ...venues.map((venue) => venue.toMapPoint(idPrefix: 'poi')),
    ..._fallbackExtraGeoJsonPoints,
  ];
}

List<MapPoint> _buildHeatmapPoints(List<MapPoint> geoJsonPoints) {
  return [...geoJsonPoints, ..._fallbackExtraHeatmapPoints];
}

const List<MapVenue> _fallbackFeaturedVenues = [
  MapVenue(
    id: 'hope-sesame',
    name: '庙前冰室（Hope & Sesame）',
    longitude: 121.4718,
    latitude: 31.2232,
    kind: 'pub',
    rating: 4.9,
    address: '上海市黄浦区复兴中路 579',
    distance: '约2.0km',
    tags: ['鸡尾酒吧', '中式复古风'],
    iconAsset: _MapAssets.pub,
    imageAsset: _MapAssets.barImage,
  ),
  MapVenue(
    id: 'speak-low',
    name: 'Speak Low（彼楼）',
    longitude: 121.4734,
    latitude: 31.2251,
    kind: 'bistro',
    rating: 4.9,
    address: '上海市黄浦区复兴中路 579',
    distance: '约1.7km',
    tags: ['经典吧台', 'Speakeasy'],
    iconAsset: _MapAssets.bistro,
    imageAsset: _MapAssets.speakLowImage,
  ),
  MapVenue(
    id: 'janes-hooch',
    name: 'Janes and Hooch',
    longitude: 121.4686,
    latitude: 31.2203,
    kind: 'party',
    rating: 4.5,
    address: '上海市黄浦区巨鹿路 158',
    distance: '约2.4km',
    tags: ['派对', '经典调酒'],
    iconAsset: _MapAssets.party,
    imageAsset: _MapAssets.janesImage,
  ),
  MapVenue(
    id: 'play-house',
    name: 'Play House 电音夜店',
    longitude: 121.4749,
    latitude: 31.2208,
    kind: 'craft',
    rating: 4.8,
    address: '上海市黄浦区淮海中路 333',
    distance: '约2.8km',
    tags: ['精酿', '现场音乐'],
    iconAsset: _MapAssets.craft,
    imageAsset: _MapAssets.playHouseImage,
  ),
];

const List<MapPoint> _fallbackExtraGeoJsonPoints = [
  MapPoint(
    id: 'poi-found-158',
    name: 'Found 158',
    longitude: 121.4667,
    latitude: 31.2215,
    kind: 'bistro',
    weight: 4.2,
  ),
  MapPoint(
    id: 'poi-julu',
    name: '巨鹿路小酒馆',
    longitude: 121.4696,
    latitude: 31.2242,
    kind: 'pub',
    weight: 4.0,
  ),
  MapPoint(
    id: 'poi-fuxing',
    name: '复兴公园酒廊',
    longitude: 121.4755,
    latitude: 31.2228,
    kind: 'party',
    weight: 3.9,
  ),
  MapPoint(
    id: 'poi-sinan',
    name: '思南精酿',
    longitude: 121.4724,
    latitude: 31.2192,
    kind: 'craft',
    weight: 3.8,
  ),
];

const List<MapPoint> _fallbackExtraHeatmapPoints = [
  MapPoint(
    id: 'heat-xintiandi-a',
    name: '新天地热区 A',
    longitude: 121.4726,
    latitude: 31.2239,
    kind: 'heat',
    weight: 7.5,
  ),
  MapPoint(
    id: 'heat-xintiandi-b',
    name: '新天地热区 B',
    longitude: 121.4705,
    latitude: 31.2219,
    kind: 'heat',
    weight: 6.8,
  ),
  MapPoint(
    id: 'heat-fuxing-a',
    name: '复兴中路热区 A',
    longitude: 121.4741,
    latitude: 31.2218,
    kind: 'heat',
    weight: 6.0,
  ),
  MapPoint(
    id: 'heat-huangpi-a',
    name: '黄陂南路热区 A',
    longitude: 121.4687,
    latitude: 31.2236,
    kind: 'heat',
    weight: 5.5,
  ),
];
