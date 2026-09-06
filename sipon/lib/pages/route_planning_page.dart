import 'package:flutter/material.dart';

class RoutePlanningPage extends StatefulWidget {
  const RoutePlanningPage({super.key});

  @override
  State<RoutePlanningPage> createState() => _RoutePlanningPageState();
}

class _RoutePlanningPageState extends State<RoutePlanningPage> {
  static const _brand = Color(0xFF9A3D78);
  static const _ink = Color(0xFF252229);
  static const _muted = Color(0xFF8F8790);

  final List<_BarPlace> _nearbyBars = const [
    _BarPlace('庙前冰室（Hope & Sesame）', '黄浦区复兴中路 579', '450m'),
    _BarPlace('Speak Low（彼楼）', '黄浦区复兴中路 579', '620m'),
    _BarPlace('Janes and Hooch', '黄浦区巨鹿路 158', '1.1km'),
    _BarPlace('Play House 电音夜店', '黄浦区淮海中路 333', '1.4km'),
    _BarPlace('武康路精酿工坊', '徐汇区武康路 388', '1.8km'),
  ];

  _BarPlace? _start;
  _BarPlace? _end;
  final List<_BarPlace?> _stops = [];

  Future<void> _pick(_RouteStopType type, {int? stopIndex}) async {
    final used = {_start, _end, ..._stops}.whereType<_BarPlace>().toSet();
    final selected = await showModalBottomSheet<_BarPlace>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(
                '选择酒吧',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            for (final bar in _nearbyBars)
              ListTile(
                enabled:
                    !used.contains(bar) ||
                    (type == _RouteStopType.stop && _stops[stopIndex!] == bar),
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFEDF7),
                  child: Icon(Icons.local_bar_outlined, color: _brand),
                ),
                title: Text(
                  bar.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${bar.address}  |  ${bar.distance}'),
                onTap: () => Navigator.of(context).pop(bar),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      switch (type) {
        case _RouteStopType.start:
          _start = selected;
        case _RouteStopType.stop:
          _stops[stopIndex!] = selected;
        case _RouteStopType.end:
          _end = selected;
      }
    });
  }

  void _createRoute() {
    if (_start == null || _end == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择起点酒吧和终点酒吧')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已规划 ${_start!.name} 至 ${_end!.name} 的路线')),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFBF8F9),
    appBar: AppBar(
      title: const Text('规划路线', style: TextStyle(fontWeight: FontWeight.w800)),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          const Text(
            '用酒吧串起今晚的路线',
            style: TextStyle(
              color: _ink,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '起点和终点为必填项，可按实际行程添加途径酒吧。',
            style: TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          _RoutePlaceTile(
            label: '起点酒吧',
            required: true,
            icon: Icons.trip_origin_rounded,
            bar: _start,
            onTap: () => _pick(_RouteStopType.start),
          ),
          for (var index = 0; index < _stops.length; index++)
            _RoutePlaceTile(
              label: '途径酒吧 ${index + 1}',
              icon: Icons.more_horiz_rounded,
              bar: _stops[index],
              onTap: () => _pick(_RouteStopType.stop, stopIndex: index),
              onRemove: () => setState(() => _stops.removeAt(index)),
            ),
          TextButton.icon(
            onPressed: _stops.length >= 3
                ? null
                : () => setState(() => _stops.add(null)),
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加途径酒吧'),
            style: TextButton.styleFrom(
              foregroundColor: _brand,
              alignment: Alignment.centerLeft,
            ),
          ),
          _RoutePlaceTile(
            label: '终点酒吧',
            required: true,
            icon: Icons.location_on_rounded,
            bar: _end,
            onTap: () => _pick(_RouteStopType.end),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _createRoute,
            icon: const Icon(Icons.alt_route_rounded),
            label: const Text('生成路线'),
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

enum _RouteStopType { start, stop, end }

class _BarPlace {
  const _BarPlace(this.name, this.address, this.distance);
  final String name;
  final String address;
  final String distance;
}

class _RoutePlaceTile extends StatelessWidget {
  const _RoutePlaceTile({
    required this.label,
    required this.icon,
    required this.bar,
    required this.onTap,
    this.required = false,
    this.onRemove,
  });
  final String label;
  final IconData icon;
  final _BarPlace? bar;
  final VoidCallback onTap;
  final bool required;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: const Color(0xFF9A3D78)),
        title: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: label),
              if (required)
                const TextSpan(
                  text: ' *',
                  style: TextStyle(color: Color(0xFFD65252)),
                ),
            ],
          ),
        ),
        subtitle: Text(
          bar?.name ?? '点击选择酒吧',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: onRemove == null
            ? const Icon(Icons.chevron_right_rounded)
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: '移除途径点',
                onPressed: onRemove,
              ),
      ),
    ),
  );
}
