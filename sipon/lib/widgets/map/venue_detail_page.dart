import 'package:flutter/material.dart';

import '../../pages/venue_map_half_page.dart';
import '../../services/map/api_venue_detail_repository.dart';
import '../../services/map/map_models.dart';
import 'venue_detail_view.dart';

/// 独立的全屏地点详情页。
///
/// 与地图页的 [VenueSheetSurface] 共用 [VenueDetailContent]，供首页酒吧推荐、
/// 打卡页附近酒吧等非地图入口点击后全屏打开某个地点/酒吧的详情。
/// 数据源内部对非数字 id（演示数据）自动回退 Mock。
class VenueDetailPage extends StatefulWidget {
  const VenueDetailPage({super.key, required this.venue});

  final MapVenue venue;

  @override
  State<VenueDetailPage> createState() => _VenueDetailPageState();
}

class _VenueDetailPageState extends State<VenueDetailPage> {
  final _scrollController = ScrollController();
  bool _openingMap = false;

  /// 详情数据源：数字 id 走真接口，演示数据自动回退 Mock。
  final _repository = SiponApiVenueDetailRepository();

  Future<void> _openMap(MapVenue venue) async {
    if (_openingMap) return;
    final longitude = venue.longitude;
    final latitude = venue.latitude;
    if (!longitude.isFinite ||
        !latitude.isFinite ||
        longitude.abs() > 180 ||
        latitude.abs() > 90 ||
        (longitude == 0 && latitude == 0)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('该地点暂无可用位置')));
      return;
    }

    _openingMap = true;
    try {
      await openVenueMapHalfPage<void>(context, venue);
    } finally {
      _openingMap = false;
    }
  }

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
      onAddressTap: _openMap,
      repository: _repository,
    ),
  );
}
