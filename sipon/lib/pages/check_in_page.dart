import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/map/map_display_options.dart';
import '../services/map/map_models.dart';
import '../services/map/map_scene_controller.dart';
import '../services/map/sipon_map_host.dart';
import '../services/map/sipon_map_widget.dart';
import '../services/sipon_api_service.dart';
import '../widgets/map/venue_detail_page.dart';

/// 一级入口以底部弹窗展示，二级的记录页面仍然通过路由全屏打开。
class CheckInPage extends StatefulWidget {
  const CheckInPage({super.key});

  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  static const _brand = Color(0xFF9A3D78);

  /// 附近酒吧的中心点：取一片酒吧密集的区域做演示锚点。
  static const _centerLongitude = 121.4718;
  static const _centerLatitude = 31.2232;

  /// 接口拉取失败时兜底的演示数据（无 barId，不可真正打卡）。
  static const _fallbackBars = [
    _NearbyBar(
      '庙前冰室（Hope & Sesame）',
      '黄浦区复兴中路 579',
      '450m',
      4.9,
      121.4718,
      31.2232,
      MapVenueKind.pub,
      false,
    ),
    _NearbyBar(
      'Speak Low（彼楼）',
      '黄浦区复兴中路 579',
      '620m',
      4.9,
      121.4734,
      31.2251,
      MapVenueKind.bistro,
      false,
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

  final SiponApiService _api = SiponApiService();

  List<_NearbyBar> _bars = _fallbackBars;
  bool _loadingBars = true;

  late final MapSceneController _scene;

  @override
  void initState() {
    super.initState();
    _scene = MapSceneController.create(
      onViewportSettled: (_) {},
      onVenueTapped: (_) {},
      onBlankTapped: () {},
    );
    _loadNearbyBars();
  }

  @override
  void dispose() {
    _scene.detach();
    super.dispose();
  }

  /// 拉取附近真实酒吧；失败时保留演示数据，页面可用但不能真正打卡。
  Future<void> _loadNearbyBars() async {
    try {
      final list = await _api.getNearbyBars(
        longitude: _centerLongitude,
        latitude: _centerLatitude,
        radiusMeters: 3000,
      );
      final parsed = [
        for (final item in list.whereType<Map>())
          _NearbyBar.tryParse(item.cast<String, dynamic>()),
      ].whereType<_NearbyBar>().toList();
      if (!mounted) return;
      setState(() {
        if (parsed.isNotEmpty) {
          _bars = parsed;
        }
        _loadingBars = false;
      });
      await _renderBars();
    } on Exception {
      if (mounted) {
        setState(() => _loadingBars = false);
      }
    }
  }

  Future<void> _handleMapCreated(SiponMapHost host) async {
    await _scene.attach(host, city: '上海', style: MapBaseStyle.standard);
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
                      _loadingBars ? '正在加载附近酒吧…' : '${_bars.length} 家可打卡',
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
      side: const BorderSide(color: Color(0xFFF0E9ED)),
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

class _CheckInCommentPage extends StatefulWidget {
  const _CheckInCommentPage({required this.bar});
  final _NearbyBar bar;

  @override
  State<_CheckInCommentPage> createState() => _CheckInCommentPageState();
}

class _CheckInCommentPageState extends State<_CheckInCommentPage> {
  /// 打卡附图上限，与后端 CheckInRequest.mediaUrls 的 maxItems 对齐。
  static const int _maxImages = 9;
  static const int _maxUploadBytes = 10 * 1024 * 1024;

  final _controller = TextEditingController();
  final SiponApiService _api = SiponApiService();
  final ImagePicker _picker = ImagePicker();
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

  /// 选择打卡附图，超出上限时提示。
  Future<void> _pickImage() async {
    if (_images.length >= _maxImages) {
      _showMessage('最多添加 $_maxImages 张图片');
      return;
    }
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() => _images.add(file));
    } on Exception {
      if (mounted) {
        _showMessage('图片选择失败，请重试');
      }
    }
  }

  /// 逐张上传打卡图片（purpose=check_in），返回内容 URL 列表。
  Future<List<String>> _uploadImages() async {
    final urls = <String>[];
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
      urls.add('/api/uploads/$mediaId/content');
    }
    return urls;
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
    final barId = widget.bar.barId;
    if (barId == null) {
      _showMessage('该酒吧暂不支持打卡');
      return;
    }
    if (_submitting) return;

    setState(() => _submitting = true);
    FocusScope.of(context).unfocus();
    try {
      final mediaUrls = await _uploadImages();
      await _api.createCheckIn({
        'barId': barId,
        'rating': _rating,
        if (_controller.text.trim().isNotEmpty)
          'content': _controller.text.trim(),
        'visibility': 'public',
        'visitedAt': DateTime.now().toUtc().toIso8601String(),
        if (mediaUrls.isNotEmpty) 'mediaUrls': mediaUrls,
      });
      if (!mounted) return;
      _showMessage('打卡成功');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on Exception catch (error) {
      if (!mounted) return;
      _showMessage('打卡失败：$error');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
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
    ),
  );
}
