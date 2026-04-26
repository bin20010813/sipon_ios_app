import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late MapController _mapController;
  bool _showHeatmap = true;

  // Mapbox 访问令牌
  static const String _mapboxAccessToken =
      'pk.eyJ1IjoiYnNndWl2enNxIiwiYSI6ImNtbmpxYjdzZzBtajcycXM0aG1xNDdoN2YifQ.WjHfteUnM7ZBkihAhI1TUw';

  void _toggleHeatmap() {
    setState(() {
      _showHeatmap = !_showHeatmap;
    });
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
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
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: const LatLng(39.9042, 116.4074), // 北京坐标
          initialZoom: 10.0,
          minZoom: 2.0,
          maxZoom: 18.0,
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/tiles/{z}/{x}/{y}@2x?access_token=$_mapboxAccessToken',
            additionalOptions: {'accessToken': _mapboxAccessToken},
            tileSize: 512,
          ),
          if (_showHeatmap) _buildHeatmapLayer(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildLegend(),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'zoom_in',
            onPressed: () {
              _mapController.move(
                _mapController.camera.center,
                _mapController.camera.zoom + 1,
              );
            },
            tooltip: '放大',
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'zoom_out',
            onPressed: () {
              _mapController.move(
                _mapController.camera.center,
                _mapController.camera.zoom - 1,
              );
            },
            tooltip: '缩小',
            child: const Icon(Icons.remove),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'location',
            backgroundColor: Theme.of(context).colorScheme.secondary,
            onPressed: () {
              // 定位到北京
              _mapController.move(const LatLng(39.9042, 116.4074), 12.0);
            },
            tooltip: '北京',
            child: const Icon(Icons.location_on),
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapLayer() {
    // 热力图层示例数据
    return CircleLayer(
      circles: [
        // 示例数据：北京多个热点位置
        CircleMarker(
          point: const LatLng(39.9042, 116.4074),
          radius: 20,
          color: Colors.red.withValues(alpha: 0.7),
          borderStrokeWidth: 2,
          borderColor: Colors.red,
        ),
        CircleMarker(
          point: const LatLng(39.9020, 116.4070),
          radius: 15,
          color: Colors.orange.withValues(alpha: 0.7),
          borderStrokeWidth: 2,
          borderColor: Colors.orange,
        ),
        CircleMarker(
          point: const LatLng(39.9060, 116.4080),
          radius: 12,
          color: Colors.yellow.withValues(alpha: 0.7),
          borderStrokeWidth: 2,
          borderColor: Colors.yellow,
        ),
        CircleMarker(
          point: const LatLng(39.9000, 116.4100),
          radius: 10,
          color: Colors.lightGreen.withValues(alpha: 0.7),
          borderStrokeWidth: 2,
          borderColor: Colors.lightGreen,
        ),
        CircleMarker(
          point: const LatLng(39.9100, 116.4000),
          radius: 8,
          color: Colors.blue.withValues(alpha: 0.7),
          borderStrokeWidth: 2,
          borderColor: Colors.blue,
        ),
      ],
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
