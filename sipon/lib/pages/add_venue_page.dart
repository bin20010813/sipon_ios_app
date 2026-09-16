import 'package:flutter/material.dart';

import '../pages/language_transform.dart';
import '../services/map/map_models.dart';
import '../services/sipon_api_client.dart';
import '../services/sipon_api_service.dart';
import '../services/sipon_city_controller.dart';
import '../widgets/map/map_theme.dart';
import '../widgets/map/venue_common.dart';
import '../widgets/sipon_city_picker.dart';

class AddVenuePage extends StatefulWidget {
  const AddVenuePage({super.key});

  @override
  State<AddVenuePage> createState() => _AddVenuePageState();
}

class _AddVenuePageState extends State<AddVenuePage> {
  final _formKey = GlobalKey<FormState>();
  final _api = SiponApiService();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _longitudeController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _mediaUrlsController = TextEditingController();

  MapVenueKind _kind = MapVenueKind.pub;
  bool _submitting = false;
  bool _cityInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cityInitialized) return;
    _cityInitialized = true;
    _cityController.text = SiponCityScope.controllerOf(context).city;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _longitudeController.dispose();
    _latitudeController.dispose();
    _descriptionController.dispose();
    _mediaUrlsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;

    final longitude = _parseCoordinate(_longitudeController.text);
    final latitude = _parseCoordinate(_latitudeController.text);
    final mediaUrls = _mediaUrlsController.text
        .split(RegExp(r'[\n,，]+'))
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .take(9)
        .toList(growable: false);

    setState(() => _submitting = true);
    try {
      await _api.createPoiSubmission({
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'longitude': longitude,
        'latitude': latitude,
        'city': _emptyToNull(_cityController),
        'subtypeCode': _kind.id,
        'description': _emptyToNull(_descriptionController),
        'mediaUrls': mediaUrls,
      });
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

  double? _parseCoordinate(String value) => double.tryParse(value.trim());

  String? _requiredText(String? value) {
    if (value == null || value.trim().isEmpty) return '请填写此项';
    return null;
  }

  String? _coordinateValidator(String? value, {required bool longitude}) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null) return '请填写有效坐标';
    if (longitude && (parsed < -180 || parsed > 180)) return '经度范围 -180 到 180';
    if (!longitude && (parsed < -90 || parsed > 90)) return '纬度范围 -90 到 90';
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
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.62,
        maxChildSize: 0.96,
        builder: (context, scrollController) {
          return Material(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: Form(
              key: _formKey,
              child: CustomScrollView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _Header(onSubmit: _submit, submitting: _submitting)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _VenueFormPreview(
                            name: _nameController.text.trim().isEmpty
                                ? text.t('未命名酒吧')
                                : _nameController.text.trim(),
                            address: _addressController.text.trim().isEmpty
                                ? text.t('地点位置')
                                : _addressController.text.trim(),
                            kind: _kind,
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
                            label: text.t('详细地址'),
                            hint: text.t('街道门牌、商场楼层或地标'),
                            icon: Icons.location_on_outlined,
                            validator: _requiredText,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          _VenueTextField(
                            controller: _cityController,
                            label: text.t('城市'),
                            hint: text.t('上海'),
                            icon: Icons.location_city_rounded,
                            validator: _requiredText,
                          ),
                          const SizedBox(height: 18),
                          _FieldLabel(text.t('地点类型')),
                          const SizedBox(height: 10),
                          _KindSelector(
                            selected: _kind,
                            onChanged: (kind) => setState(() => _kind = kind),
                          ),
                          const SizedBox(height: 18),
                          _FieldLabel(text.t('地图坐标')),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _VenueTextField(
                                  controller: _longitudeController,
                                  label: text.t('经度'),
                                  hint: '121.4737',
                                  icon: Icons.explore_outlined,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                  validator: (value) => _coordinateValidator(value, longitude: true),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _VenueTextField(
                                  controller: _latitudeController,
                                  label: text.t('纬度'),
                                  hint: '31.2304',
                                  icon: Icons.explore_rounded,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                  validator: (value) => _coordinateValidator(value, longitude: false),
                                ),
                              ),
                            ],
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
                          const SizedBox(height: 12),
                          _VenueTextField(
                            controller: _mediaUrlsController,
                            label: text.t('图片链接'),
                            hint: text.t('每行一个图片 URL，最多 9 张'),
                            icon: Icons.image_outlined,
                            minLines: 2,
                            maxLines: 4,
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _submitting ? null : _submit,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
          );
        },
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
        padding: const EdgeInsets.fromLTRB(18, 10, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD2D0D2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
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
                  onPressed: submitting ? null : () => Navigator.of(context).maybePop(),
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

class _VenueFormPreview extends StatelessWidget {
  const _VenueFormPreview({
    required this.name,
    required this.address,
    required this.kind,
    this.imageUrl,
  });

  final String name;
  final String address;
  final MapVenueKind kind;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x11000000)),
        boxShadow: const [
          BoxShadow(color: Color(0x129A3D78), blurRadius: 18, offset: Offset(0, 8)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: VenueImage(
                imageUrl: imageUrl,
                assetPath: MapAssets.coverForIndex(kind.index),
                width: 90,
                height: 102,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.t(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MapDesign.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      VenueTag(label: text.t(kind.label)),
                      VenueTag(label: text.t('待审核')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_outlined, color: MapDesign.brand, size: 17),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          text.t(address),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MapDesign.muted,
                            fontSize: 12,
                            letterSpacing: 0,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    text.t('审核通过后进入地图点位'),
                    style: const TextStyle(
                      color: MapDesign.muted,
                      fontSize: 12,
                      letterSpacing: 0,
                    ),
                  ),
                ],
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

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final kind in MapVenueKind.values)
          ChoiceChip(
            label: Text(text.t(kind.label)),
            avatar: Image.asset(kind.iconAsset, width: 18, height: 18),
            selected: selected == kind,
            onSelected: (_) => onChanged(kind),
            showCheckmark: false,
            selectedColor: const Color(0x1F9A3D78),
            backgroundColor: const Color(0xFFF7F2F5),
            side: BorderSide(
              color: selected == kind ? MapDesign.brand : const Color(0x00000000),
            ),
            labelStyle: TextStyle(
              color: selected == kind ? MapDesign.brand : MapDesign.ink,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
      onChanged: onChanged,
      textInputAction: maxLines == 1 ? TextInputAction.next : TextInputAction.newline,
      decoration: InputDecoration(
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

