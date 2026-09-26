import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../pages/language_transform.dart';
import '../services/map/checkin_pin_icon.dart';
import '../services/map/map_display_options.dart';
import '../services/map/map_models.dart';
import '../services/map/map_place_result.dart';
import '../services/map/map_scene_controller.dart';
import '../services/map/map_viewport.dart';
import '../services/map/sipon_map_host.dart';
import '../services/map/sipon_map_widget.dart';
import '../services/sipon_api_client.dart';
import '../services/sipon_api_service.dart';
import '../widgets/map/map_theme.dart';
import '../widgets/sipon_city_picker.dart';

class AddVenuePage extends StatefulWidget {
  const AddVenuePage({super.key});

  @override
  State<AddVenuePage> createState() => _AddVenuePageState();
}

class _AddVenuePageState extends State<AddVenuePage> {
  static const _maxImageCount = 3;

  final _formKey = GlobalKey<FormState>();
  final _api = SiponApiService();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _openingHoursController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();
  final _photos = <XFile>[];

  late final MapSceneController _scene;
  MapVenueKind _kind = MapVenueKind.pub;
  bool _submitting = false;
  bool _cityInitialized = false;
  bool _mapReady = false;
  Timer? _addressSearchTimer;
  int _addressSearchRevision = 0;
  List<MapPlaceResult> _addressSuggestions = const [];
  bool _addressSearching = false;
  bool _addressSearchFailed = false;
  bool _addressResolved = false;

  @override
  void initState() {
    super.initState();
    _scene = MapSceneController.create(
      onViewportSettled: _handleViewportSettled,
      onVenueTapped: (_) {},
      onBlankTapped: () {},
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cityInitialized) return;
    _cityInitialized = true;
    _cityController.text = SiponCityScope.controllerOf(context).city;
  }

  @override
  void dispose() {
    _addressSearchTimer?.cancel();
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _longitudeController.dispose();
    _latitudeController.dispose();
    _phoneController.dispose();
    _openingHoursController.dispose();
    _descriptionController.dispose();
    _scene.detach();
    super.dispose();
  }

  Future<void> _handleMapCreated(SiponMapHost host) async {
    final city = SiponCityScope.controllerOf(context).city;
    await _scene.attach(host, city: city, style: MapBaseStyle.standard);
    if (!_scene.isAttached) return;

    final center = mapCenterForCity(city);
    await _scene.focusOn(
      longitude: center.longitude,
      latitude: center.latitude,
    );
    final viewport = await _scene.readViewport();
    if (!mounted) return;
    _setSelectedLocation(viewport?.center ?? center);
    setState(() => _mapReady = true);
    if (_addressController.text.trim().isNotEmpty && !_addressResolved) {
      _handleAddressChanged(_addressController.text);
    }
  }

  void _handleViewportSettled(MapViewport viewport) {
    _setSelectedLocation(viewport.center);
  }

  void _setSelectedLocation(MapLatLng location) {
    if (!location.longitude.isFinite || !location.latitude.isFinite) return;
    _longitudeController.text = location.longitude.toStringAsFixed(6);
    _latitudeController.text = location.latitude.toStringAsFixed(6);
    if (mounted) setState(() {});
  }

  void _handleAddressChanged(String value) {
    _addressSearchTimer?.cancel();
    final query = value.trim();
    final revision = ++_addressSearchRevision;
    setState(() {
      _addressSuggestions = const [];
      _addressSearching = query.isNotEmpty;
      _addressSearchFailed = false;
      _addressResolved = false;
    });
    if (query.isEmpty || !_mapReady) return;
    _addressSearchTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_searchAddress(query, revision));
    });
  }

  void _handleAddressSubmitted(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    if (_addressSuggestions.isNotEmpty) {
      _selectAddress(_addressSuggestions.first);
      return;
    }
    _addressSearchTimer?.cancel();
    final revision = ++_addressSearchRevision;
    setState(() {
      _addressSearching = true;
      _addressSearchFailed = false;
      _addressResolved = false;
    });
    unawaited(_searchAddress(query, revision, selectFirst: true));
  }

  Future<void> _searchAddress(
    String query,
    int revision, {
    bool selectFirst = false,
  }) async {
    try {
      final results = await _scene.searchPlaces(query);
      if (!mounted || revision != _addressSearchRevision) return;
      if (selectFirst && results.isNotEmpty) {
        _selectAddress(results.first);
        return;
      }
      setState(() {
        _addressSuggestions = results;
        _addressSearching = false;
      });
    } on Exception {
      if (!mounted || revision != _addressSearchRevision) return;
      setState(() {
        _addressSuggestions = const [];
        _addressSearching = false;
        _addressSearchFailed = true;
      });
    }
  }

  void _selectAddress(MapPlaceResult place) {
    _addressSearchTimer?.cancel();
    _addressSearchRevision++;
    _addressController.text = place.address.isEmpty
        ? place.name
        : place.address;
    if (place.city.isNotEmpty) _cityController.text = place.city;
    _setSelectedLocation(place.location);
    setState(() {
      _addressSuggestions = const [];
      _addressSearching = false;
      _addressSearchFailed = false;
      _addressResolved = true;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(
      _scene.focusOn(
        longitude: place.location.longitude,
        latitude: place.location.latitude,
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;

    if (!_mapReady) {
      _showMessage('地图还在加载，请稍候再提交');
      return;
    }
    final longitude = _parseCoordinate(_longitudeController.text);
    final latitude = _parseCoordinate(_latitudeController.text);
    if (longitude == null || latitude == null) return;

    setState(() => _submitting = true);
    try {
      final mediaUrls = await _uploadImages(_photos, purpose: 'poi_storefront');
      // One photo gallery in the UI; retain the legacy field for API compatibility.
      final body = <String, Object?>{
        'name': _nameController.text.trim(),
        'longitude': longitude,
        'latitude': latitude,
        'subtypeCode': _kind.id,
        if (mediaUrls.isNotEmpty) ...{
          'storefrontMediaUrls': mediaUrls,
          'mediaUrls': mediaUrls,
        },
      };
      _addOptional(body, 'address', _emptyToNull(_addressController));
      _addOptional(body, 'city', _emptyToNull(_cityController));
      _addOptional(body, 'phoneNumber', _emptyToNull(_phoneController));
      _addOptional(body, 'openingHours', _emptyToNull(_openingHoursController));
      _addOptional(body, 'description', _emptyToNull(_descriptionController));
      await _api.createPoiSubmission(body);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SiponApiException catch (error) {
      _showMessage(error.message ?? '提交失败，请稍后重试');
    } on Exception {
      _showMessage('提交失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _emptyToNull(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  void _addOptional(Map<String, Object?> body, String key, String? value) {
    if (value != null) body[key] = value;
  }

  double? _parseCoordinate(String value) => double.tryParse(value.trim());

  Future<void> _pickImages() async {
    if (_photos.length >= _maxImageCount) {
      _showMessage('最多上传 3 张图片');
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text(
              '选择图片来源',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;
      setState(() => _photos.add(image));
    } on Exception {
      _showMessage('图片选择失败，请重试');
    }
  }

  Future<List<String>> _uploadImages(
    List<XFile> images, {
    required String purpose,
  }) async {
    final urls = <String>[];
    for (final image in images) {
      final bytes = await image.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw Exception('图片超过 10MiB 限制，请更换图片');
      }
      final response = await _api.uploadMedia(
        fileBytes: bytes,
        filename: image.name,
        mimeType: _mimeTypeFor(image),
        purpose: purpose,
      );
      final mediaId = _extractMediaId(response);
      if (mediaId == null) throw Exception('图片上传失败，请重试');
      urls.add('/api/uploads/$mediaId/content');
    }
    return urls;
  }

  String? _extractMediaId(dynamic response) {
    if (response is! Map) return null;
    final raw =
        response['mediaId'] ??
        response['id'] ??
        (response['data'] is Map ? response['data']['mediaId'] : null);
    final id = raw?.toString().trim();
    return id == null || id.isEmpty ? null : id;
  }

  String _mimeTypeFor(XFile image) {
    final mime = image.mimeType?.trim();
    if (mime != null && mime.isNotEmpty) return mime;
    final name = image.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.heic') || name.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) return '请填写此项';
    return null;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true,
      body: Material(
        color: Colors.white,
        child: Form(
          key: _formKey,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _Header(onSubmit: _submit, submitting: _submitting),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _LocationPicker(
                        mapReady: _mapReady,
                        onHostReady: _handleMapCreated,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        text.t('拖动地图，让中心定位点对准酒吧位置'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: MapDesign.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel(text.t('基础信息')),
                      const SizedBox(height: 10),
                      _VenueTextField(
                        controller: _nameController,
                        label: text.t('酒馆名称'),
                        hint: text.t('例如：复兴公园酒廊'),
                        icon: Icons.storefront_rounded,
                        validator: _requiredText,
                        onChanged: (_) => setState(() {}),
                      ),

                      const SizedBox(height: 12),
                      _VenueTextField(
                        controller: _addressController,
                        label: text.t('酒馆地址'),
                        hint: text.t('输入地址或地点名称'),
                        icon: Icons.place_outlined,
                        textInputAction: TextInputAction.search,
                        onChanged: _handleAddressChanged,
                        onFieldSubmitted: _handleAddressSubmitted,
                      ),
                      if (_addressController.text.trim().isNotEmpty &&
                          !_addressResolved) ...[
                        const SizedBox(height: 6),
                        _AddressSearchResults(
                          results: _addressSuggestions,
                          searching: _addressSearching,
                          failed: _addressSearchFailed,
                          onSelected: _selectAddress,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        text.t('选择搜索结果可自动定位地图，也可拖动地图微调'),
                        style: const TextStyle(
                          color: MapDesign.muted,
                          fontSize: 11,
                        ),
                      ),

                      const SizedBox(height: 18),
                      _FieldLabel(text.t('地点类型')),
                      const SizedBox(height: 10),
                      _KindSelector(
                        selected: _kind,
                        onChanged: (kind) => setState(() => _kind = kind),
                      ),
                      const SizedBox(height: 18),
                      _VenueTextField(
                        controller: _phoneController,
                        label: text.t('联系电话（可选）'),
                        hint: text.t('例如：021-12345678'),
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      _VenueTextField(
                        controller: _openingHoursController,
                        label: text.t('营业时间（可选）'),
                        hint: text.t('例如：18:00-02:00'),
                        icon: Icons.schedule_rounded,
                      ),
                      const SizedBox(height: 12),
                      _VenueImageSection(
                        title: text.t('照片'),
                        images: _photos,
                        canAdd: _photos.length < _maxImageCount,
                        onAdd: _pickImages,
                        onRemove: (index) =>
                            setState(() => _photos.removeAt(index)),
                      ),

                      const SizedBox(height: 18),
                      _FieldLabel(text.t('补充信息')),
                      const SizedBox(height: 10),
                      _VenueTextField(
                        controller: _descriptionController,
                        label: text.t('酒馆介绍'),
                        hint: text.t('氛围、酒单特色、适合什么场景'),
                        icon: Icons.notes_rounded,
                        minLines: 3,
                        maxLines: 5,
                      ),

                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_rounded),
                        label: Text(text.t(_submitting ? '提交中...' : '提交酒馆信息')),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: MapDesign.brand,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFE2C9D9),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        text.t('提交后会进入审核，通过后展示在地图酒吧地点中。'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: MapDesign.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSubmit, required this.submitting});

  final VoidCallback onSubmit;
  final bool submitting;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text.t('新增酒馆'),
                        style: const TextStyle(
                          color: MapDesign.ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text.t('补充地图里还没有的好去处'),
                        style: const TextStyle(
                          color: MapDesign.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: text.t('关闭'),
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationPicker extends StatelessWidget {
  const _LocationPicker({required this.mapReady, required this.onHostReady});

  /// 中心图钉尺寸，宽高比与 CheckInPinPainter 设计稿（22×28）一致。
  static const _pinSize = Size(30, 38);

  final bool mapReady;
  final void Function(SiponMapHost host) onHostReady;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 250,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SiponMapWidget(
              initialStyleId: MapBaseStyle.standard.id,
              onHostReady: onHostReady,
            ),
            // 中心定位浮标：红色图钉，底部向上抬一个浮标高度，
            // 让针尖正好落在地图中心点。
            IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: _pinSize.height),
                  child: SizedBox(
                    width: _pinSize.width,
                    height: _pinSize.height,
                    child: const CustomPaint(painter: CheckInPinPainter()),
                  ),
                ),
              ),
            ),
            if (!mapReady)
              const IgnorePointer(
                child: ColoredBox(
                  color: Color(0x66FFFFFF),
                  child: Center(
                    child: CircularProgressIndicator(color: MapDesign.brand),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KindSelector extends StatelessWidget {
  const _KindSelector({required this.selected, required this.onChanged});

  final MapVenueKind selected;
  final ValueChanged<MapVenueKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final kind in MapVenueKind.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(text.t(kind.label)),
                avatar: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    selected == kind ? MapDesign.brand : MapDesign.ink,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(kind.iconAsset, width: 18, height: 18),
                ),
                selected: selected == kind,
                onSelected: (_) => onChanged(kind),
                showCheckmark: false,
                selectedColor: const Color(0x1F9A3D78),
                backgroundColor: const Color(0xFFF7F2F5),
                side: BorderSide(
                  color: selected == kind
                      ? MapDesign.brand
                      : const Color(0x00000000),
                ),
                labelStyle: TextStyle(
                  color: selected == kind ? MapDesign.brand : MapDesign.ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VenueTextField extends StatelessWidget {
  const _VenueTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.validator,
    this.keyboardType,
    this.minLines = 1,
    this.maxLines = 1,
    this.onChanged,
    this.onFieldSubmitted,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      textInputAction:
          textInputAction ??
          (maxLines == 1 ? TextInputAction.next : TextInputAction.newline),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xFFF7F2F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0x00000000)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: MapDesign.brand, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
        ),
        labelStyle: const TextStyle(
          color: MapDesign.muted,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        hintStyle: const TextStyle(color: Color(0x998F8790), letterSpacing: 0),
      ),
    );
  }
}

class _AddressSearchResults extends StatelessWidget {
  const _AddressSearchResults({
    required this.results,
    required this.searching,
    required this.failed,
    required this.onSelected,
  });

  final List<MapPlaceResult> results;
  final bool searching;
  final bool failed;
  final ValueChanged<MapPlaceResult> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          text.t(
            searching
                ? '正在搜索地点…'
                : failed
                ? '地点搜索失败，请重试'
                : '未找到地点',
          ),
          style: const TextStyle(color: MapDesign.muted, fontSize: 12),
        ),
      );
    }

    final visible = results.take(5).toList();
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE6E3E5)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < visible.length; index++) ...[
            if (index > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              leading: const Icon(Icons.place_outlined, color: MapDesign.brand),
              title: Text(
                visible[index].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: visible[index].address.isEmpty
                  ? null
                  : Text(
                      visible[index].address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              onTap: () => onSelected(visible[index]),
            ),
          ],
        ],
      ),
    );
  }
}

class _VenueImageSection extends StatelessWidget {
  const _VenueImageSection({
    required this.title,
    required this.images,
    required this.canAdd,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final List<XFile> images;
  final bool canAdd;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    const slotSize = 104.0;
    const gap = 8.0;
    final slots = List.generate(3, (index) {
      if (index < images.length) {
        return SizedBox(
          width: slotSize,
          height: slotSize,
          child: _ImagePreview(
            image: images[index],
            onRemove: () => onRemove(index),
          ),
        );
      }
      if (index == images.length && canAdd) {
        return SizedBox(
          width: slotSize,
          height: slotSize,
          child: _AddImageSlot(onTap: onAdd),
        );
      }
      return SizedBox(
        width: slotSize,
        height: slotSize,
        child: const _EmptyImageSlot(),
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: MapDesign.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
            Text(
              '${images.length}/3',
              style: const TextStyle(
                color: MapDesign.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: slotSize + 14,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.hardEdge,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              physics: const ClampingScrollPhysics(),
              clipBehavior: Clip.hardEdge,
              itemCount: slots.length,
              separatorBuilder: (_, _) => const SizedBox(width: gap),
              itemBuilder: (_, index) => SizedBox(
                width: slotSize,
                height: slotSize,
                child: slots[index],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddImageSlot extends StatelessWidget {
  const _AddImageSlot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F2F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x1A9A3D78)),
        ),
        child: const Icon(Icons.add_a_photo_outlined, color: MapDesign.brand),
      ),
    );
  }
}

class _EmptyImageSlot extends StatelessWidget {
  const _EmptyImageSlot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x1A9A3D78)),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.image, required this.onRemove});

  final XFile image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            File(image.path),
            width: 78,
            height: 78,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const ColoredBox(
              color: Color(0xFFF7F2F5),
              child: SizedBox(
                width: 78,
                height: 78,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
        Positioned(
          top: 3,
          right: 3,
          child: GestureDetector(
            onTap: onRemove,
            child: const CircleAvatar(
              radius: 11,
              backgroundColor: Color(0xCC292B32),
              child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: MapDesign.ink,
        fontSize: 15,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }
}
