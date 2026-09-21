import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/map/api_venue_detail_repository.dart';
import '../../services/map/map_models.dart';
import 'venue_detail_view.dart';
import 'venue_mini_map.dart';

/// 独立的全屏地点详情页。
///
/// 与地图页的 [VenueSheetSurface] 共用 [VenueDetailContent]，供首页酒吧推荐、
/// 打卡页附近酒吧等非地图入口点击后全屏打开某个地点/酒吧的详情。
/// 数据源内部对非数字 id（演示数据）自动回退 Mock。
///
/// 详情常驻在一张 [DraggableScrollableSheet] 上（与地图 Tab 同款机制）：
/// - 初始 extent = 1.0，就是普通全屏详情；
/// - 点地址「查看地图」：挂载地图层、sheet 收到 0.55——看起来是页面下沉、
///   上方露出聚焦该地点的地图（[VenueMiniMap]）；
/// - 之后在详情任意处上滑/下滑（或点顶部把手）在半屏 ↔ 全屏间联动；
/// - 收回地图 = sheet 回到 1.0 后卸载地图层；系统返回逐级触发。
/// 地图 Tab 的链路（MapPage / VenueSheetController / VenueMapHalfPage）零改动。
class VenueDetailPage extends StatefulWidget {
  const VenueDetailPage({super.key, required this.venue});

  final MapVenue venue;

  @override
  State<VenueDetailPage> createState() => _VenueDetailPageState();
}

class _VenueDetailPageState extends State<VenueDetailPage> {
  /// 半屏档（sheet extent）与地图露出高度：详情占下方 55%、地图露上方 45%，
  /// 与地图 Tab 的 half 档语义对齐。数值快照，不引用地图 Tab 的文件。
  static const double _halfExtent = 0.55;
  static const double _mapFraction = 0.45;
  // minChildSize 与 maxChildSize 都为 1 时，DraggableScrollableSheet 会在
  // 详情数据加载阶段吞掉内层列表的垂直拖动。保留肉眼不可见的调度范围，
  // 让拖动可以正常转交给详情滚动视图。
  static const double _fullscreenMinExtent = 0.999;
  static const Duration _motionDuration = Duration(milliseconds: 420);
  static const Curve _motionCurve = Curves.easeOutCubic;

  final _repository = SiponApiVenueDetailRepository();
  final _sheetController = DraggableScrollableController();

  /// 地图层是否挂载。挂载即视为展开态：系统返回先逐级收回，
  /// 收回动画结束后才允许 pop 整页。
  bool _mapMounted = false;

  /// 展开/收回动画进行中的防抖标志。
  bool _mapAnimating = false;

  /// sheet 的 builder 每帧都会被调用，而详情子树很重：这里按
  /// scrollController 的同一性缓存 widget 实例，让 Flutter 在拖动帧里
  /// 整体跳过 rebuild，只有装饰与把手随 extent 重绘。
  ScrollController? _sheetScrollController;
  bool? _sheetMapMounted;
  Widget? _sheetDetail;

  Widget _detailInSheet(ScrollController controller, double topInset) {
    if (!identical(_sheetScrollController, controller) ||
        _sheetMapMounted != _mapMounted) {
      _sheetScrollController = controller;
      _sheetMapMounted = _mapMounted;
      _sheetDetail = VenueDetailContent(
        venue: widget.venue,
        scrollController: controller,
        opacity: 1,
        // 独立详情页没有地图面板负责传递状态栏高度，关闭按钮和吸顶标签栏
        // 需要自行避开 iOS 刘海区域。
        topInset: topInset,
        bottomOverlayInset: 0,
        onClose: () => Navigator.of(context).pop(),
        onAddressTap: (_) => unawaited(_expandMap()),
        onMapClose: _mapMounted ? () => unawaited(_collapseMap()) : null,
        repository: _repository,
      );
    }

    return _sheetDetail!;
  }

  /// 全屏进度：0 = 半屏，1 = 全屏。驱动圆角/阴影随档位收敛。
  double get _fullscreenProgress {
    if (!_sheetController.isAttached) {
      return 1;
    }
    final progress = (_sheetController.size - _halfExtent) / (1 - _halfExtent);
    return progress.clamp(0.0, 1.0).toDouble();
  }

  /// 地址点击进入「地图半屏」：地图挂载，详情面板下沉到半屏。
  Future<void> _expandMap() async {
    final longitude = widget.venue.longitude;
    final latitude = widget.venue.latitude;
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
    if (_mapMounted || _mapAnimating) return;

    _mapAnimating = true;
    setState(() => _mapMounted = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await _animateSheetTo(_halfExtent);
    } finally {
      _mapAnimating = false;
    }
  }

  /// 从「地图半屏」退出地图：先让详情盖住地图，再卸载地图层。
  Future<void> _collapseMap() async {
    if (!_mapMounted || _mapAnimating) return;

    _mapAnimating = true;
    try {
      await _animateSheetTo(1.0);
      if (mounted) {
        setState(() => _mapMounted = false);
      }
    } finally {
      _mapAnimating = false;
    }
  }

  Future<void> _animateSheetTo(double extent) {
    if (!_sheetController.isAttached) {
      return Future<void>.value();
    }
    return _sheetController.animateTo(
      extent,
      duration: _motionDuration,
      curve: _motionCurve,
    );
  }

  /// 返回只处理地图半屏这一层：全屏详情直接退出当前页面，
  /// 半屏地图才先收起地图回到普通详情。
  void _handlePopInvoked() {
    if (_mapAnimating) return;

    if (_sheetController.size > _halfExtent + 0.01) {
      Navigator.of(context).pop();
      return;
    }
    unawaited(_collapseMap());
  }

  /// 半屏态点地图空白处收回地图（全屏态地图被详情盖住，点不到）。
  void _handleMapBlankTapped() {
    if (_mapMounted &&
        !_mapAnimating &&
        _sheetController.size <= _halfExtent + 0.01) {
      unawaited(_collapseMap());
    }
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapHeight = MediaQuery.sizeOf(context).height * _mapFraction;
    final statusBarTop = MediaQuery.paddingOf(context).top;

    final mapLayer = _mapMounted
        ? VenueMiniMap(
            venue: widget.venue,
            onBlankTapped: _handleMapBlankTapped,
          )
        : null;

    return PopScope(
      canPop: !_mapMounted,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handlePopInvoked();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // 地图层：常驻在 sheet 后面。初始与全屏档被详情完全盖住，
            // 下沉后从交界处露出——挂载即可，无需位移动画。
            // key 让地图层插入/移除时 diff 不至于把 sheet 当成「删除+新建」
            // 重建——否则旧 element 未 detach、新 element attach 时会撞
            // 「controller is already attached」断言。
            if (mapLayer != null)
              Positioned(
                key: const ValueKey('venue-mini-map'),
                left: 0,
                right: 0,
                top: 0,
                height: mapHeight,
                child: DecoratedBox(
                  // attach 完成前的兜底底色，接近标准底图的浅色。
                  decoration: const BoxDecoration(color: Color(0xFFF3F0F2)),
                  child: mapLayer,
                ),
              ),
            Positioned.fill(
              key: const ValueKey('venue-detail-sheet'),
              child: DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: 1.0,
                minChildSize: _mapMounted ? _halfExtent : _fullscreenMinExtent,
                maxChildSize: 1.0,
                // 松手后吸附到半屏/全屏两档：无 snap 时面板会停在任意
                // 中间位置（比如 0.92），观感很尴尬。min/max 自动是吸附点。
                snap: true,
                snapAnimationDuration: _motionDuration,
                // 拖到最小档不要把详情页整个 pop 掉，收回地图由我们接管。
                shouldCloseOnMinExtent: false,
                builder: (context, scrollController) => ListenableBuilder(
                  listenable: _sheetController,
                  builder: (context, _) {
                    final progress = _fullscreenProgress;
                    final corner = 16 * progress;

                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(corner),
                        ),
                        // 半屏态给顶部阴影撑出层次，全屏态消失。
                        boxShadow: progress < 1
                            ? const [
                                BoxShadow(
                                  color: Color(0x29000000),
                                  blurRadius: 18,
                                  offset: Offset(0, -6),
                                ),
                              ]
                            : const [],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(corner),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: _detailInSheet(
                                scrollController,
                                statusBarTop,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
