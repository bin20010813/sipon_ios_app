import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late MapboxMap mapboxMap;
  bool _showHeatmap = true;

  // TODO: 替换为你的 Mapbox 访问令牌
  // 从 https://account.mapbox.com/tokens/ 获取
  static const String _mapboxAccessToken = 'YOUR_MAPBOX_ACCESS_TOKEN';

  void _toggleHeatmap() {
    setState(() {
      _showHeatmap = !_showHeatmap;
    });
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    this.mapboxMap = mapboxMap;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Mapbox 地图'),
        actions: [
          Tooltip(
            message: _showHeatmap ? '隐藏热力图' : '显示热力图',
            child: IconButton(
              icon: Icon(_showHeatmap ? Icons.thermostat : Icons.opacity),
              onPressed: _toggleHeatmap,
            ),
          ),
        ],
      ),
      body: MapWidget(
        key: const ValueKey('mapbox'),
        resourceOptions: ResourceOptions(
          accessToken: _mapboxAccessToken,
          baseUrl: 'https://api.mapbox.com',
        ),
        cameraOptions: CameraOptions(
          center: Point(coordinates: Position(116.4074, 39.9042)).toJson(),
          zoom: 10.0,
        ),
        styleUri: MapboxStyles.OUTDOORS,
        onMapCreated: _onMapCreated,
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildLegend(),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'zoom_in',
            onPressed: () async {
              final currentZoom = await mapboxMap.getZoom();
              await mapboxMap.easeTo(
                CameraOptions(zoom: currentZoom + 1),
                MapAnimationOptions(duration: 300),
              );
            },
            tooltip: '放大',
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'zoom_out',
            onPressed: () async {
              final currentZoom = await mapboxMap.getZoom();
              await mapboxMap.easeTo(
                CameraOptions(zoom: currentZoom - 1),
                MapAnimationOptions(duration: 300),
              );
            },
            tooltip: '缩小',
            child: const Icon(Icons.remove),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'location',
            backgroundColor: Theme.of(context).colorScheme.secondary,
            onPressed: () async {
              // 定位到北京
              await mapboxMap.easeTo(
                CameraOptions(
                  center: Point(
                    coordinates: Position(116.4074, 39.9042),
                  ).toJson(),
                  zoom: 12.0,
                ),
                MapAnimationOptions(duration: 500),
              );
            },
            tooltip: '北京',
            child: const Icon(Icons.location_on),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    if (!_showHeatmap) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '热力图',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _buildLegendItem('高', Colors.red),
          _buildLegendItem('较高', Colors.orange),
          _buildLegendItem('中等', Colors.yellow),
          _buildLegendItem('较低', Colors.lightGreen),
          _buildLegendItem('低', Colors.blue),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
