import 'package:flutter/material.dart';

import '../services/map/map_display_options.dart';
import '../services/map/map_models.dart';
import '../services/map/map_scene_controller.dart';
import '../services/map/sipon_map_host.dart';
import '../services/map/sipon_map_widget.dart';
import '../widgets/map/venue_detail_view.dart';

/// 一级入口以底部弹窗展示，二级的记录页面仍然通过路由全屏打开。
class CheckInPage extends StatefulWidget {
  const CheckInPage({super.key});

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  static const _brand = Color(0xFF9A3D78);

  static const _bars = [
    _NearbyBar(
      '庙前冰室（Hope & Sesame）',
      '黄浦区复兴中路 579',
      '450m',
      4.9,
      121.4718,
      31.2232,
      MapVenueKind.pub,
      true,
    ),
    _NearbyBar(
      'Speak Low（彼楼）',
      '黄浦区复兴中路 579',
      '620m',
      4.9,
      121.4734,
      31.2251,
      MapVenueKind.bistro,
      true,
    ),
    _NearbyBar(
      'Janes and Hooch',
      '黄浦区巨鹿路 158',
      '1.1km',
      4.5,
      121.4686,
      31.2203,
      MapVenueKind.party,
      false,
    ),
    _NearbyBar(
      'Play House 电音夜店',
      '黄浦区淮海中路 333',
      '1.4km',
      4.8,
      121.4667,
      31.2182,
      MapVenueKind.livehouse,
      false,
    ),
  ];

  late final MapSceneController _scene;

  @override
  void initState() {
    super.initState();
    _scene = MapSceneController.create(
      onViewportSettled: (_) {},
      onVenueTapped: (_) {},
      onBlankTapped: () {},
    );
  }

  @override
  void dispose() {
    _scene.detach();
    super.dispose();
  }

  Future<void> _handleMapCreated(SiponMapHost host) async {
    await _scene.attach(host, city: '上海', style: MapBaseStyle.standard);
    await _scene.render(
      MapSceneFrame(
        circlePoints: [
          for (final bar in _bars)
            MapPoint(
              id: 'check-in-${bar.name}',
              name: bar.name,
              longitude: bar.longitude,
              latitude: bar.latitude,
              kind: bar.kind,
              weight: 1,
            ),
        ],
        heatmapPoints: const [],
        markers: [
          for (final bar in _bars)
            MapMarkerSpec(
              venueId: bar.name,
              label: bar.name,
              longitude: bar.longitude,
              latitude: bar.latitude,
              kind: bar.kind,
            ),
        ],
        layerMode: MapLayerMode.pointsOnly,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return Material(
      color: const Color(0xFFFBF8F9),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: height,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD2CBD0),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '打卡酒吧',
                        style: TextStyle(
                          color: Color(0xFF252229),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: height * 0.28,
                child: SiponMapWidget(
                  initialStyleId: MapBaseStyle.standard.id,
                  onHostReady: _handleMapCreated,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Row(
                  children: [
                    const Text(
                      '附近酒吧',
                      style: TextStyle(
                        color: Color(0xFF252229),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_bars.length} 家可打卡',
                      style: const TextStyle(
                        color: Color(0xFF8F8790),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  itemCount: _bars.length,
                  itemBuilder: (context, index) =>
                      _NearbyBarTile(bar: _bars[index], brand: _brand),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NearbyBar {
  const _NearbyBar(
    this.name,
    this.address,
    this.distance,
    this.rating,
    this.longitude,
    this.latitude,
    this.kind,
    this.checkedIn,
  );

  final String name;
  final String address;
  final String distance;
  final double rating;
  final double longitude;
  final double latitude;
  final MapVenueKind kind;
  final bool checkedIn;

  MapVenue get venue => MapVenue(
    id: name,
    name: name,
    longitude: longitude,
    latitude: latitude,
    kind: kind,
    rating: rating,
    address: address,
    distance: distance,
    tags: const [],
    imageAsset: switch (name) {
      '庙前冰室（Hope & Sesame）' => MapAssets.barImage,
      'Speak Low（彼楼）' => MapAssets.speakLowImage,
      'Janes and Hooch' => MapAssets.janesImage,
      'Play House 电音夜店' => MapAssets.playHouseImage,
      _ => MapAssets.coverForIndex(0),
    },
  );
}

class _NearbyBarTile extends StatelessWidget {
  const _NearbyBarTile({required this.bar, required this.brand});

  final _NearbyBar bar;
  final Color brand;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 6),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: Color(0xFFF0E9ED)),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.fromLTRB(14, 1, 8, 1),
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => _VenueDetailPage(venue: bar.venue),
        ),
      ),
      title: Text(
        bar.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text('${bar.distance}  ·  ${bar.address}'),
      trailing: SizedBox(
        width: 76,
        height: 34,
        child: bar.checkedIn
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F2E8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    '已打卡',
                    style: TextStyle(
                      color: Color(0xFF6C8C72),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            : FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _CheckInCommentPage(bar: bar),
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: brand,
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('打卡'),
              ),
      ),
    ),
  );
}

class _VenueDetailPage extends StatefulWidget {
  const _VenueDetailPage({required this.venue});

  final MapVenue venue;

  @override
  State<_VenueDetailPage> createState() => _VenueDetailPageState();
}

class _VenueDetailPageState extends State<_VenueDetailPage> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: VenueDetailContent(
      venue: widget.venue,
      scrollController: _scrollController,
      opacity: 1,
      // 独立详情页没有地图面板负责传递状态栏高度，关闭按钮和吸顶标签栏
      // 需要自行避开 iOS 刘海区域。
      topInset: MediaQuery.paddingOf(context).top,
      bottomOverlayInset: 0,
      onClose: () => Navigator.of(context).pop(),
    ),
  );
}

class _CheckInCommentPage extends StatefulWidget {
  const _CheckInCommentPage({required this.bar});
  final _NearbyBar bar;

  @override
  State<_CheckInCommentPage> createState() => _CheckInCommentPageState();
}

class _CheckInCommentPageState extends State<_CheckInCommentPage> {
  final _controller = TextEditingController();
  int _rating = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_rating == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先给这家酒吧评分')));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('打卡已记录')));
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFBF8F9),
    appBar: AppBar(
      title: const Text('记录打卡', style: TextStyle(fontWeight: FontWeight.w800)),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.bar.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF252229),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.bar.address,
            style: const TextStyle(color: Color(0xFF8F8790)),
          ),
          const SizedBox(height: 28),
          const Text('本次体验', style: TextStyle(fontWeight: FontWeight.w700)),
          Row(
            children: [
              for (var index = 1; index <= 5; index++)
                IconButton(
                  onPressed: () => setState(() => _rating = index),
                  icon: Icon(
                    index <= _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: const Color(0xFFE09A35),
                    size: 30,
                  ),
                  tooltip: '$index 星',
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: '写下这次的酒、音乐或遇见的人...',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
                borderSide: BorderSide(color: Color(0xFFF0E9ED)),
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check_rounded),
              label: const Text('完成打卡'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF9A3D78),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
