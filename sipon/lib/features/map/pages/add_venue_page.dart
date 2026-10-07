import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:sipon/shared/localization/language_transform.dart';

import 'package:sipon/features/map/widgets/checkin_pin_icon.dart';
import 'package:sipon/features/map/models/map_display_options.dart';
import 'package:sipon/features/map/models/map_models.dart';
import 'package:sipon/features/map/controllers/map_scene_controller.dart';
import 'package:sipon/features/map/models/map_viewport.dart';
import 'package:sipon/features/map/platform/sipon_map_host.dart';
import 'package:sipon/features/map/platform/map_engine.dart';
import 'package:sipon/features/map/widgets/sipon_map_widget.dart';

import 'package:sipon/shared/services/sipon_api_client.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/app/theme/sipon_theme_colors.dart';
import 'package:sipon/shared/widgets/sipon_city_picker.dart';
import 'package:sipon/shared/widgets/sipon_message.dart';

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

  final _longitudeController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _openingHoursController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _picker = ImagePicker();
  final _photos = <XFile>[];

  late final MapSceneController _scene;
  MapVenueKind? _kind;
  bool _submitting = false;
  bool _mapReady = false;
  final _debugId = DateTime.now().microsecondsSinceEpoch;
  int _submissionAttempt = 0;

  void _debugLog(String message, {Object? error, StackTrace? stackTrace}) {
    if (!kDebugMode) return;
    debugPrint('[AddVenue][$_debugId][attempt=$_submissionAttempt] $message');
    if (error is SiponApiException) {
      debugPrint(
        '[AddVenue] HTTP error: status=${error.statusCode}, '
        'code=${error.code}, path=${error.path}, requestId=${error.requestId}',
      );
    } else if (error != null) {
      // FormatException may contain the response body; log only the type.
      debugPrint('[AddVenue] exceptionType=${error.runtimeType}');
    }
    if (stackTrace != null) {
      debugPrintStack(label: '[AddVenue] stack', stackTrace: stackTrace);
    }
  }

  String _responseShape(dynamic response) {
    if (response is Map) {
      final data = response['data'];
      return 'type=${response.runtimeType}, keys=${response.keys.toList()}, '
          'dataKeys=${data is Map ? data.keys.toList() : null}';
    }
    return 'type=${response.runtimeType}';
  }

  @override
  void initState() {
    super.initState();
    _scene = MapSceneController.create(
      onViewportSettled: _handleViewportSettled,
      onVenueTapped: (_) {},
      onBlankTapped: () {},
    );
    _debugLog('page.init locationMode=coordinatesOnly, addressSearch=disabled');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _longitudeController.dispose();
    _latitudeController.dispose();
    _phoneController.dispose();
    _openingHoursController.dispose();
    _descriptionController.dispose();
    _scene.detach();
    super.dispose();
  }

  Future<void> _handleMapCreated(SiponMapHost host) async {
    final timer = Stopwatch()..start();
    var stage = 'attach';
    _debugLog('map.init.start engine=${selectMapEngine().name}');
    try {
      final city = SiponCityScope.controllerOf(context).city;
      await _scene.attach(host, city: city, style: MapBaseStyle.standard);
      _debugLog(
        'map.attach.complete attached=${_scene.isAttached}, '
        'elapsedMs=${timer.elapsedMilliseconds}',
      );
      if (!_scene.isAttached) {
        _debugLog('map.init.blocked reason=notAttached');
        return;
      }

      final center = mapCenterForCity(city);
      stage = 'focus';
      await _scene.focusOn(
        longitude: center.longitude,
        latitude: center.latitude,
      );
      stage = 'readViewport';
      final viewport = await _scene.readViewport();
      _debugLog(
        'map.viewport.read hasViewport=${viewport != null}, '
        'hasScreenCenter=${viewport?.screenCenter != null}, mounted=$mounted',
      );
      if (!mounted) return;
      // Android must report the actual screen center after its coordinate
      // adapter. A bounds midpoint is not accurate enough for a submission.
      if (selectMapEngine() == MapEngine.tianditu &&
          viewport?.screenCenter == null) {
        _debugLog('map.init.blocked reason=missingScreenCenter');
        return;
      }
      _setSelectedLocation(viewport?.center ?? center);
      setState(() => _mapReady = true);
      _debugLog('map.init.ready elapsedMs=${timer.elapsedMilliseconds}');
    } catch (error, stackTrace) {
      _debugLog(
        'map.init.failed stage=$stage, elapsedMs=${timer.elapsedMilliseconds}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  void _handleViewportSettled(MapViewport viewport) {
    _debugLog(
      'map.viewport.settled mapReady=$_mapReady, '
      'hasScreenCenter=${viewport.screenCenter != null}',
    );
    if (selectMapEngine() == MapEngine.tianditu &&
        viewport.screenCenter == null) {
      _debugLog('map.location.ignored reason=missingScreenCenter');
      return;
    }
    _setSelectedLocation(viewport.center);
  }

  void _setSelectedLocation(MapLatLng location) {
    if (!location.longitude.isFinite || !location.latitude.isFinite) {
      _debugLog('map.location.ignored reason=nonFiniteCoordinate');
      return;
    }
    _longitudeController.text = location.longitude.toStringAsFixed(6);
    _latitudeController.text = location.latitude.toStringAsFixed(6);
    _debugLog(
      'map.location.selected source=mapCenter, '
      'longitude=${_longitudeController.text}, latitude=${_latitudeController.text}',
    );
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (_submitting) {
      _debugLog('submit.blocked reason=alreadySubmitting');
      return;
    }
    _submissionAttempt++;
    _debugLog(
      'submit.start engine=${selectMapEngine().name}, mapReady=$_mapReady, '
      'photoCount=${_photos.length}, nameLength=${_nameController.text.trim().length}',
    );
    if (!_formKey.currentState!.validate()) {
      _debugLog('submit.blocked reason=formValidation');
      return;
    }
    _debugLog('submit.validation.passed');

    if (!_mapReady) {
      _debugLog(
        'submit.blocked reason=mapNotReady attached=${_scene.isAttached}',
      );
      _showMessage('地图还在加载，请稍候再提交');
      return;
    }
    final longitude = _parseCoordinate(_longitudeController.text);
    final latitude = _parseCoordinate(_latitudeController.text);
    if (longitude == null || latitude == null) {
      _debugLog(
        'submit.blocked reason=coordinateParseFailed, '
        'longitudeParsed=${longitude != null}, latitudeParsed=${latitude != null}',
      );
      return;
    }
    _debugLog(
      'submit.coordinates.checked longitude=$longitude, latitude=$latitude, '
      'finite=${longitude.isFinite && latitude.isFinite}, '
      'inRange=${longitude >= -180 && longitude <= 180 && latitude >= -90 && latitude <= 90}',
    );

    final timer = Stopwatch()..start();
    var stage = 'uploadImages';
    setState(() => _submitting = true);
    try {
      _debugLog('images.upload.start count=${_photos.length}');
      final mediaUrls = await _uploadImages(_photos, purpose: 'poi_storefront');
      _debugLog('images.upload.complete count=${mediaUrls.length}');
      // One photo gallery in the UI; retain the legacy field for API compatibility.
      final body = <String, Object?>{
        'longitude': longitude,
        'latitude': latitude,
        if (_kind != null) 'subtypeCode': _kind!.id,
        if (mediaUrls.isNotEmpty) ...{
          'storefrontMediaUrls': mediaUrls,
          'mediaUrls': mediaUrls,
        },
      };

      body['name'] = _nameController.text.trim();
      _addOptional(body, 'phoneNumber', _emptyToNull(_phoneController));
      _addOptional(body, 'openingHours', _emptyToNull(_openingHoursController));
      _addOptional(body, 'description', _emptyToNull(_descriptionController));
      stage = 'createPoiSubmission';
      _debugLog(
        'submission.request.start endpoint=/api/poi-submissions, '
        'fields=${body.keys.toList()}, subtypeCode=${_kind?.id}, '
        'mediaCount=${mediaUrls.length}, locationMode=coordinatesOnly, '
        'longitude=$longitude, latitude=$latitude, '
        'hasAddress=${body.containsKey('address')}, hasCity=${body.containsKey('city')}, '
        'phoneLength=${_phoneController.text.trim().length}, '
        'openingHoursLength=${_openingHoursController.text.trim().length}, '
        'descriptionLength=${_descriptionController.text.trim().length}',
      );
      final response = await _api.createPoiSubmission(body);
      _debugLog(
        'submission.request.complete ${_responseShape(response)}, '
        'elapsedMs=${timer.elapsedMilliseconds}, mounted=$mounted',
      );
      if (!mounted) return;
      stage = 'navigateBack';
      Navigator.of(context).pop(true);
    } on SiponApiException catch (error, stackTrace) {
      _debugLog(
        'submit.failed stage=$stage, elapsedMs=${timer.elapsedMilliseconds}',
        error: error,
        stackTrace: stackTrace,
      );
      _showMessage(error.message ?? '提交失败，请稍后重试', type: SiponMessageType.error);
    } on Exception catch (error, stackTrace) {
      _debugLog(
        'submit.failed stage=$stage, elapsedMs=${timer.elapsedMilliseconds}',
        error: error,
        stackTrace: stackTrace,
      );
      _showMessage('提交失败，请稍后重试', type: SiponMessageType.error);
    } catch (error, stackTrace) {
      _debugLog(
        'submit.unhandled stage=$stage, elapsedMs=${timer.elapsedMilliseconds}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      _debugLog('submit.end elapsedMs=${timer.elapsedMilliseconds}');
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
      backgroundColor: context.siponColors.elevatedSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              '选择图片来源',
              style: TextStyle(
                color: Theme.of(sheetContext).colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
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
    if (source == null) {
      _debugLog('image.pick.cancelled stage=chooseSource');
      return;
    }

    _debugLog('image.pick.start source=${source.name}');
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 85,
      );
      _debugLog(
        'image.pick.complete selected=${image != null}, mounted=$mounted',
      );
      if (image == null || !mounted) return;
      setState(() => _photos.add(image));
      _debugLog('image.pick.added photoCount=${_photos.length}');
    } on Exception catch (error, stackTrace) {
      _debugLog('image.pick.failed', error: error, stackTrace: stackTrace);
      _showMessage('图片选择失败，请重试', type: SiponMessageType.error);
    }
  }

  Future<List<String>> _uploadImages(
    List<XFile> images, {
    required String purpose,
  }) async {
    final urls = <String>[];
    for (final image in images) {
      final index = urls.length + 1;
      final timer = Stopwatch()..start();
      var stage = 'readBytes';
      try {
        _debugLog('image.read.start index=$index');
        final bytes = await image.readAsBytes();
        final mimeType = _mimeTypeFor(image);
        _debugLog(
          'image.read.complete index=$index, bytes=${bytes.length}, '
          'mimeType=$mimeType, elapsedMs=${timer.elapsedMilliseconds}',
        );
        if (bytes.length > 10 * 1024 * 1024) {
          _debugLog('image.upload.blocked index=$index, reason=exceeds10MiB');
          throw Exception('图片超过 10MiB 限制，请更换图片');
        }
        stage = 'uploadMedia';
        _debugLog(
          'image.upload.start index=$index, endpoint=/api/uploads, '
          'purpose=$purpose, purposeLocation=multipartField',
        );
        final response = await _api.uploadMedia(
          fileBytes: bytes,
          filename: image.name,
          mimeType: mimeType,
          purpose: purpose,
        );
        stage = 'extractMediaId';
        final mediaId = _extractMediaId(response);
        _debugLog(
          'image.upload.response index=$index, ${_responseShape(response)}, '
          'hasMediaId=${mediaId != null}',
        );
        if (mediaId == null) {
          _debugLog('image.upload.failed index=$index, reason=missingMediaId');
          throw Exception('图片上传失败，请重试');
        }
        urls.add('/api/uploads/$mediaId/content');
        _debugLog(
          'image.upload.complete index=$index, '
          'urlPattern=/api/uploads/{mediaId}/content, '
          'elapsedMs=${timer.elapsedMilliseconds}',
        );
      } catch (error, stackTrace) {
        _debugLog(
          'image.failed index=$index, stage=$stage, '
          'elapsedMs=${timer.elapsedMilliseconds}',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
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

  void _showMessage(
    String message, {
    SiponMessageType type = SiponMessageType.info,
  }) {
    if (!mounted) return;
    showSiponMessage(context, message, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      resizeToAvoidBottomInset: true,
      body: Material(
        color: scheme.surface,
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
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
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
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? text.t('请输入酒馆名称')
                            : null,
                        hint: text.t('例如：复兴公园酒廊'),
                        icon: Icons.storefront_rounded,

                        onChanged: (_) => setState(() {}),
                      ),

                      const SizedBox(height: 18),
                      _FieldLabel('${text.t('地点类型')}（${text.t('可选')}）'),
                      const SizedBox(height: 10),
                      _KindSelector(
                        selected: _kind,
                        onChanged: (kind) =>
                            setState(() => _kind = _kind == kind ? null : kind),
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
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.onPrimary,
                                ),
                              )
                            : const Icon(Icons.cloud_upload_rounded),
                        label: Text(text.t(_submitting ? '提交中...' : '提交酒馆信息')),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          disabledBackgroundColor: scheme.onSurface.withValues(
                            alpha: 0.12,
                          ),
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
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
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
    final scheme = Theme.of(context).colorScheme;

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
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text.t('补充地图里还没有的好去处'),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
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
    final scheme = Theme.of(context).colorScheme;
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
              IgnorePointer(
                child: ColoredBox(
                  color: scheme.surface.withValues(alpha: 0.4),
                  child: Center(
                    child: CircularProgressIndicator(color: scheme.primary),
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

  final MapVenueKind? selected;
  final ValueChanged<MapVenueKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final scheme = Theme.of(context).colorScheme;
    final siponColors = context.siponColors;

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
                    selected == kind ? scheme.primary : scheme.onSurface,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(kind.iconAsset, width: 18, height: 18),
                ),
                selected: selected == kind,
                onSelected: (_) => onChanged(kind),
                showCheckmark: false,
                selectedColor: scheme.primary.withValues(alpha: 0.12),
                backgroundColor: siponColors.subtleSurface,
                side: BorderSide(
                  color: selected == kind ? scheme.primary : Colors.transparent,
                ),
                labelStyle: TextStyle(
                  color: selected == kind ? scheme.primary : scheme.onSurface,
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

    this.keyboardType,
    this.minLines = 1,
    this.maxLines = 1,
    this.onChanged,
    this.validator,
  });

  final FormFieldValidator<String>? validator;
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;

  final TextInputType? keyboardType;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final siponColors = context.siponColors;
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      validator: validator,
      textInputAction: maxLines == 1
          ? TextInputAction.next
          : TextInputAction.newline,
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
        fillColor: siponColors.subtleSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.error, width: 1.2),
        ),
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
          letterSpacing: 0,
        ),
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
    final scheme = Theme.of(context).colorScheme;
    const slotWidth = 104.0;
    const slotHeight = slotWidth * 4 / 3;
    const gap = 8.0;
    final slots = List.generate(3, (index) {
      if (index < images.length) {
        return SizedBox(
          width: slotWidth,
          height: slotHeight,
          child: _ImagePreview(
            image: images[index],
            onRemove: () => onRemove(index),
          ),
        );
      }
      if (index == images.length && canAdd) {
        return SizedBox(
          width: slotWidth,
          height: slotHeight,
          child: _AddImageSlot(onTap: onAdd),
        );
      }
      return SizedBox(
        width: slotWidth,
        height: slotHeight,
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
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
            Text(
              '${images.length}/3',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
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
          height: slotHeight,
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
                width: slotWidth,
                height: slotHeight,
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
    final scheme = Theme.of(context).colorScheme;
    final siponColors = context.siponColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: siponColors.subtleSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
        ),
        child: Icon(Icons.add_a_photo_outlined, color: scheme.primary),
      ),
    );
  }
}

class _EmptyImageSlot extends StatelessWidget {
  const _EmptyImageSlot();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final siponColors = context.siponColors;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: siponColors.subtleSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
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
    final scheme = Theme.of(context).colorScheme;
    final siponColors = context.siponColors;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ColoredBox(
            color: siponColors.subtleSurface,
            child: Image.file(
              File(image.path),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
        Positioned(
          top: 3,
          right: 3,
          child: GestureDetector(
            onTap: onRemove,
            child: CircleAvatar(
              radius: 11,
              backgroundColor: scheme.scrim.withValues(alpha: 0.8),
              // 照片上的固定深色关闭钮，白色图标保证在图片上对比度。
              child: const Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white,
              ),
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
    final scheme = Theme.of(context).colorScheme;
    return Text(
      label,
      style: TextStyle(
        color: scheme.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }
}
