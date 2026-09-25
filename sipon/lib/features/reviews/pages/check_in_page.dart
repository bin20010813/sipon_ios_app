import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../map/widgets/checkin_pin_icon.dart';
import '../../../app/theme/sipon_theme_colors.dart';
import '../../map/models/map_display_options.dart';
import '../../map/models/map_models.dart';
import '../../map/controllers/map_scene_controller.dart';
import '../../map/models/map_viewport.dart';
import '../../map/platform/sipon_map_host.dart';
import '../../map/widgets/sipon_map_widget.dart';
import '../../../shared/services/sipon_api_service.dart';
import '../../../shared/services/sipon_city_controller.dart';
import '../../../shared/services/sipon_search_preferences.dart';
import '../../map/pages/venue_detail_page.dart';
import '../widgets/review_composer.dart';
import '../../../shared/widgets/sipon_city_picker.dart';

/// 一级入口以底部弹窗展示，二级的记录页面仍然通过路由全屏打开。
class CheckInPage extends StatefulWidget {
  const CheckInPage({super.key, this.apiService});

  final SiponApiService? apiService;

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  late final SiponApiService _api;

  /// 附近酒吧每页条数。
  static const int _nearbyPageSize = 20;

  /// 地图和附近推荐共用本次获取的设备定位。
  List<_NearbyBar> _bars = [];
  SiponCityController? _cityController;
  SiponLocationPoint? _loadedAnchor;
  String? _locationError;
  int _requestVersion = 0;

  /// 首屏是否还在加载（展示「正在加载附近酒吧…」）。
  bool _loadingBars = true;

  /// 附近酒吧列表的滚动控制器。
  final ScrollController _barsController = ScrollController();

  late final MapSceneController _scene;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? SiponApiService();
    _scene = MapSceneController.create(
      onViewportSettled: (_) {},
      onVenueTapped: (_) {},
      onBlankTapped: () {},
    );
    // 偏好设置里调整搜索半径后，即时按新半径重新拉取附近酒吧。
    SiponSearchPreferences.instance.addListener(_handleRadiusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = SiponCityScope.controllerOf(context);
    if (_cityController != controller) {
      _cityController = controller;
      _loadNearbyBars();
    }
  }

  @override
  void dispose() {
    _requestVersion++;
    SiponSearchPreferences.instance.removeListener(_handleRadiusChanged);
    _barsController.dispose();
    _scene.detach();
    super.dispose();
  }

  void _handleRadiusChanged() {
    if (!mounted) return;
    _loadNearbyBars();
  }

  /// 每次打开或重试获取实际定位，以同一坐标查询偏好半径内的酒吧。
  Future<void> _loadNearbyBars() async {
    final version = ++_requestVersion;
    setState(() {
      _loadingBars = true;
      _locationError = null;
    });
    final location = await _cityController?.locateCurrentCity();
    if (!mounted || version != _requestVersion) return;
    final anchor = location?.position;
    if (anchor == null) {
      setState(() {
        _loadingBars = false;
        _locationError = switch (location?.status) {
          SiponLocateStatus.serviceDisabled => '请开启系统定位服务后重试',
          SiponLocateStatus.permissionDenied => '需要定位权限，才能推荐你附近的酒吧',
          SiponLocateStatus.permissionDeniedForever => '请在系统设置中允许 SipOn 使用定位',
          _ => '暂时无法获取当前位置，请重试',
        };
      });
      return;
    }
    final anchorChanged = _loadedAnchor != anchor;
    setState(() => _loadedAnchor = anchor);
    if (_scene.isAttached && anchorChanged) {
      await _scene.focusOn(
        longitude: anchor.longitude,
        latitude: anchor.latitude,
      );
    }
    if (!mounted || version != _requestVersion) return;
    try {
      final list = await _api.getNearbyBars(
        longitude: anchor.longitude,
        latitude: anchor.latitude,
        radiusMeters: SiponSearchPreferences.instance.radiusMeters,
        limit: _nearbyPageSize,
      );
      final parsed = [
        for (final item in list.whereType<Map>())
          _NearbyBar.tryParse(item.cast<String, dynamic>()),
      ].whereType<_NearbyBar>().toList();
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _bars = parsed;
        _loadingBars = false;
      });
      await _renderBars();
    } on Exception {
      if (mounted && version == _requestVersion) {
        setState(() {
          _loadingBars = false;
          _bars = [];
        });
      }
    }
  }

  Future<void> _handleMapCreated(SiponMapHost host) async {
    final initialAnchor = _loadedAnchor;
    if (initialAnchor == null || !mounted) return;
    await _scene.attach(
      host,
      city: _cityController?.city ?? SiponCityController.defaultCity,
      style: MapBaseStyle.standard,
      initialCenter: MapLatLng(
        longitude: initialAnchor.longitude,
        latitude: initialAnchor.latitude,
      ),
    );
    if (!mounted) return;
    // 地图准备期间若重新获取了定位，使用最新设备坐标。
    final anchor = _loadedAnchor;
    if (anchor != null && anchor != initialAnchor) {
      await _scene.focusOn(
        longitude: anchor.longitude,
        latitude: anchor.latitude,
      );
    }
    await _renderBars();
  }

  /// 把当前酒吧列表下发到地图图层。
  Future<void> _renderBars() async {
    if (!_scene.isAttached) return;
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
              // 打卡页不区分酒吧分类，统一用红色图钉浮标。
              iconCategory: checkInPinCategory,
            ),
        ],
        markers: [
          for (final bar in _bars)
            MapMarkerSpec(
              venueId: bar.name,
              label: bar.name,
              longitude: bar.longitude,
              latitude: bar.latitude,
              kind: bar.kind,
              iconCategory: checkInPinCategory,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.78;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      // 打卡面板是底部弹层，用主题浮层表面色（浅色下为白色）。
      color: context.siponColors.elevatedSurface,
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
                  // 抓手条：由次要文字色降透明度合成，两种外观下都可见。
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '打卡酒吧',
                        style: TextStyle(
                          color: scheme.onSurface,
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
                child: _loadedAnchor != null
                    ? SiponMapWidget(
                        initialStyleId: MapBaseStyle.standard.id,
                        onHostReady: _handleMapCreated,
                      )
                    : Center(
                        child: _locationError == null
                            ? const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text('正在获取当前位置…'),
                                ],
                              )
                            : Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _locationError!,
                                      textAlign: TextAlign.center,
                                    ),
                                    TextButton(
                                      onPressed: _loadNearbyBars,
                                      child: const Text('重新定位'),
                                    ),
                                  ],
                                ),
                              ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Row(
                  children: [
                    Text(
                      '你附近的酒吧',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _loadingBars
                          ? '正在加载附近酒吧…'
                          : _locationError != null
                          ? '等待定位'
                          : '${_bars.length} 家可打卡',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _barsController,
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  itemCount: _bars.length,
                  itemBuilder: (context, index) {
                    return _NearbyBarTile(
                      bar: _bars[index],
                      brand: scheme.primary,
                    );
                  },
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
    this.checkedIn, {
    this.barId,
  });

  final String name;
  final String address;
  final String distance;
  final double rating;
  final double longitude;
  final double latitude;
  final MapVenueKind kind;
  final bool checkedIn;

  /// 后端酒吧 id；为 null 的是演示数据，不能真正提交打卡。
  final int? barId;

  /// 从 getNearbyBars 响应解析；缺关键字段（id/名称/坐标）时返回 null。
  static _NearbyBar? tryParse(Map<String, dynamic> map) {
    final id = (map['id'] as num?)?.toInt() ?? (map['barId'] as num?)?.toInt();
    final name = map['name']?.toString().trim();
    final longitude = (map['longitude'] as num?)?.toDouble();
    final latitude = (map['latitude'] as num?)?.toDouble();
    if (id == null || name == null || name.isEmpty) {
      return null;
    }
    if (longitude == null || latitude == null) {
      return null;
    }
    final meters = (map['distanceMeters'] as num?)?.toDouble();
    return _NearbyBar(
      name,
      map['address']?.toString() ?? '',
      meters == null
          ? ''
          : meters >= 1000
          ? '约${(meters / 1000).toStringAsFixed(1)}km'
          : '约${meters.round()}m',
      (map['averageRating'] as num?)?.toDouble() ??
          (map['rating'] as num?)?.toDouble() ??
          0,
      longitude,
      latitude,
      MapVenueKind.fromRaw(
        map['barSubtype']?.toString() ?? map['subtype']?.toString(),
      ),
      false,
      barId: id,
    );
  }

  MapVenue get venue => MapVenue(
    id: barId?.toString() ?? name,
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
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.fromLTRB(14, 1, 8, 1),
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VenueDetailPage(venue: bar.venue),
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
                  // 已打卡：成功语义的弱底与文字成对出现。
                  color: context.siponColors.successSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '已打卡',
                    style: TextStyle(
                      color: context.siponColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
            : FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CheckInCommentPage(
                      barId: bar.barId,
                      venueName: bar.name,
                      venueAddress: bar.address,
                    ),
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

/// 打卡与地点评价共用的发布页。
class CheckInCommentPage extends StatefulWidget {
  const CheckInCommentPage({
    super.key,
    required this.barId,
    required this.venueName,
    required this.venueAddress,
    this.returnToVenue = false,
  });

  final int? barId;
  final String venueName;
  final String venueAddress;
  final bool returnToVenue;

  @override
  State<CheckInCommentPage> createState() => _CheckInCommentPageState();
}

class _CheckInCommentPageState extends State<CheckInCommentPage> {
  static const int _maxUploadBytes = 10 * 1024 * 1024;

  final _controller = TextEditingController();
  final SiponApiService _api = SiponApiService();
  final List<XFile> _images = <XFile>[];
  int _rating = 0;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 逐张上传打卡图片（purpose=check_in），返回上传媒体 ID 列表。
  Future<List<String>> _uploadImages() async {
    final mediaIds = <String>[];
    for (final file in _images) {
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxUploadBytes) {
        throw Exception('图片超过 10MiB 限制，请更换图片');
      }
      final response = await _api.uploadMedia(
        fileBytes: bytes,
        filename: file.name,
        mimeType: _mimeTypeFor(file),
        purpose: 'check_in',
      );
      final mediaId = _extractMediaId(response);
      if (mediaId == null) {
        throw Exception('图片上传失败，请重试');
      }
      mediaIds.add(mediaId);
    }
    return mediaIds;
  }

  /// 从上传响应的多种字段名中尽力提取媒体 ID。
  String? _extractMediaId(dynamic response) {
    if (response is! Map) return null;
    final raw =
        response['mediaId'] ??
        response['id'] ??
        (response['data'] is Map ? response['data']['mediaId'] : null);
    final id = raw?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// 根据文件扩展名推断图片 MIME 类型，未知扩展名统一按 JPEG 处理。
  String _mimeTypeFor(XFile file) {
    final mime = file.mimeType?.trim();
    if (mime != null && mime.isNotEmpty) return mime;

    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.heic') || name.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  /// 提交打卡：先上传附图，再 POST /api/check-ins。
  Future<void> _submit() async {
    if (_rating == 0) {
      _showMessage('请先给这家酒吧评分');
      return;
    }
    final barId = widget.barId;
    if (barId == null) {
      _showMessage('该酒吧暂不支持打卡');
      return;
    }
    if (_submitting) return;

    setState(() => _submitting = true);
    FocusScope.of(context).unfocus();
    try {
      final mediaIds = await _uploadImages();
      await _api.createCheckIn({
        'barId': barId,
        'rating': _rating,
        if (_controller.text.trim().isNotEmpty)
          'content': _controller.text.trim(),
        'visibility': 'public',
        'visitedAt': DateTime.now().toUtc().toIso8601String(),
        if (mediaIds.isNotEmpty) 'mediaIds': mediaIds,
      });
      if (!mounted) return;
      _showMessage('打卡成功');
      if (widget.returnToVenue) {
        Navigator.of(context).pop(true);
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on Exception catch (error) {
      if (!mounted) return;
      _showMessage('打卡失败：$error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _submitDraft(ReviewDraft draft) async {
    _rating = draft.rating;
    _controller.text = draft.content;
    _images
      ..clear()
      ..addAll(draft.images);
    await _submit();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    // 页面底沿用主题脚手架底色，与首页、个人页保持一致。
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    appBar: AppBar(
      title: const Text('微醺这一刻', style: TextStyle(fontWeight: FontWeight.w800)),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    body: ReviewComposer(
      venueName: widget.venueName,
      venueAddress: widget.venueAddress,
      submitLabel: '完成打卡',
      onSubmit: _submitDraft,
    ),
    // 说明：下方注释块为未参与构建的历史代码，其中浅色常量保持原样，
    // 不属于深色迁移范围，故不对其做主题替换。
    /* Padding(
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
          const SizedBox(height: 16),
          SizedBox(
            height: 76,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var index = 0; index < _images.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: FutureBuilder<List<int>>(
                            future: _images[index].readAsBytes(),
                            builder: (context, snapshot) {
                              final bytes = snapshot.data;
                              if (bytes == null) {
                                return Container(
                                  width: 76,
                                  height: 76,
                                  color: const Color(0xFFF0E9ED),
                                );
                              }
                              return Image.memory(
                                Uint8List.fromList(bytes),
                                width: 76,
                                height: 76,
                                fit: BoxFit.cover,
                              );
                            },
                          ),
                        ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: IconButton(
                            onPressed: () =>
                                setState(() => _images.removeAt(index)),
                            icon: const Icon(Icons.cancel_rounded, size: 20),
                            color: const Color(0xFF9A3D78),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 24,
                              height: 24,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_images.length < _maxImages)
                  InkWell(
                    onTap: _pickImage,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFF0E9ED)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: Color(0xFF9A3D78),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_submitting ? '打卡中…' : '完成打卡'),
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
    ), */
  );
}
