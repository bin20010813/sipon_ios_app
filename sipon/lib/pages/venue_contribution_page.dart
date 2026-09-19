import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/map/map_models.dart';
import '../services/sipon_api_client.dart';
import '../services/sipon_api_service.dart';
import '../widgets/map/map_theme.dart';
import 'language_transform.dart';

/// 地点详情「补充信息」共建页。
///
/// 面向已有地点，收集用户补充的营业时间、电话、介绍与照片，
/// 复用新增酒馆的 POI 提案接口提交，走同样的审核流程。
class VenueContributionPage extends StatefulWidget {
  /// 创建补充信息页。
  const VenueContributionPage({super.key, required this.venue});

  /// 待补充的地点基础信息。
  final MapVenue venue;

  @override
  State<VenueContributionPage> createState() => _VenueContributionPageState();
}

class _VenueContributionPageState extends State<VenueContributionPage> {
  static const _maxImageCount = 3;

  final _api = SiponApiService();
  final _picker = ImagePicker();
  final _openingHoursController = TextEditingController();
  final _phoneController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _storefrontImages = <XFile>[];
  final _menuImages = <XFile>[];
  bool _submitting = false;

  int get _imageCount => _storefrontImages.length + _menuImages.length;

  bool get _hasInput =>
      _openingHoursController.text.trim().isNotEmpty ||
      _phoneController.text.trim().isNotEmpty ||
      _descriptionController.text.trim().isNotEmpty ||
      _imageCount > 0;

  @override
  void dispose() {
    _openingHoursController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// 提交补充提案；body 结构与新增酒馆保持一致，便于审核侧统一处理。
  Future<void> _submit() async {
    final text = SiponLanguageScope.textOf(context);
    if (_submitting) return;
    if (!_hasInput) {
      _showMessage(text.t('请至少补充一项内容'));
      return;
    }

    setState(() => _submitting = true);
    try {
      final storefrontMediaUrls = await _uploadImages(
        _storefrontImages,
        purpose: 'poi_storefront',
      );
      final menuMediaUrls = await _uploadImages(
        _menuImages,
        purpose: 'poi_menu',
      );
      final body = <String, Object?>{
        'name': widget.venue.name,
        'longitude': widget.venue.longitude,
        'latitude': widget.venue.latitude,
        'subtypeCode': widget.venue.kind.id,
        if (storefrontMediaUrls.isNotEmpty)
          'storefrontMediaUrls': storefrontMediaUrls,
        if (menuMediaUrls.isNotEmpty) 'menuMediaUrls': menuMediaUrls,
        if (storefrontMediaUrls.isNotEmpty || menuMediaUrls.isNotEmpty)
          'mediaUrls': [...storefrontMediaUrls, ...menuMediaUrls],
      };
      _addOptional(body, 'openingHours', _textOf(_openingHoursController));
      _addOptional(body, 'phoneNumber', _textOf(_phoneController));
      _addOptional(body, 'description', _textOf(_descriptionController));
      await _api.createPoiSubmission(body);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SiponApiException catch (error) {
      _showMessage(error.message ?? text.t('提交失败，请稍后重试'));
    } on Exception {
      _showMessage(text.t('提交失败，请稍后重试'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String? _textOf(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  void _addOptional(Map<String, Object?> body, String key, String? value) {
    if (value != null) body[key] = value;
  }

  Future<void> _pickImages(List<XFile> target) async {
    final text = SiponLanguageScope.textOf(context);
    if (_imageCount >= _maxImageCount) {
      _showMessage(text.t('最多上传 3 张图片'));
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
            Text(
              text.t('选择图片来源'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(text.t('从相册选择')),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(text.t('拍照')),
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
      setState(() => target.add(image));
    } on Exception {
      _showMessage(text.t('图片选择失败，请重试'));
    }
  }

  Future<List<String>> _uploadImages(
    List<XFile> images, {
    required String purpose,
  }) async {
    final text = SiponLanguageScope.textOf(context);
    final urls = <String>[];
    for (final image in images) {
      final bytes = await image.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        throw Exception(text.t('图片超过 10MiB 限制，请更换图片'));
      }
      final response = await _api.uploadMedia(
        fileBytes: bytes,
        filename: image.name,
        mimeType: _mimeTypeFor(image),
        purpose: purpose,
      );
      final mediaId = _extractMediaId(response);
      if (mediaId == null) throw Exception(text.t('图片上传失败，请重试'));
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
      appBar: AppBar(
        title: Text(
          text.t('补充地点信息'),
          style: const TextStyle(
            color: MapDesign.ink,
            fontSize: 17,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _VenueSummaryCard(venue: widget.venue),
            const SizedBox(height: 18),
            _FieldLabel(text.t('补充信息')),
            const SizedBox(height: 10),
            _ContributionTextField(
              controller: _openingHoursController,
              label: text.t('营业时间（可选）'),
              hint: text.t('例如：周一至周五 18:00-02:00'),
              icon: Icons.schedule_rounded,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _ContributionTextField(
              controller: _phoneController,
              label: text.t('联系电话（可选）'),
              hint: text.t('例如：021-12345678'),
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _ContributionTextField(
              controller: _descriptionController,
              label: text.t('酒馆介绍'),
              hint: text.t('氛围、酒单特色、适合什么场景'),
              icon: Icons.notes_rounded,
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 18),
            _ContributionImageSection(
              title: text.t('店面照片'),
              images: _storefrontImages,
              imageCount: _imageCount,
              onAdd: () => _pickImages(_storefrontImages),
              onRemove: (index) =>
                  setState(() => _storefrontImages.removeAt(index)),
            ),
            const SizedBox(height: 14),
            _ContributionImageSection(
              title: text.t('菜单照片'),
              images: _menuImages,
              imageCount: _imageCount,
              onAdd: () => _pickImages(_menuImages),
              onRemove: (index) => setState(() => _menuImages.removeAt(index)),
            ),
            const SizedBox(height: 22),
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
                  : const Icon(Icons.volunteer_activism_rounded),
              label: Text(text.t(_submitting ? '提交中...' : '提交补充信息')),
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
          ],
        ),
      ),
    );
  }
}

/// 顶部地点摘要卡：让用户确认是在给哪家店补充信息。
class _VenueSummaryCard extends StatelessWidget {
  const _VenueSummaryCard({required this.venue});

  final MapVenue venue;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F5F8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(
                MapDesign.brand,
                BlendMode.srcIn,
              ),
              child: Image.asset(venue.iconAsset, width: 24, height: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        text.t(venue.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MapDesign.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: MapDesign.brandSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        text.t(venue.kind.label),
                        style: const TextStyle(
                          color: MapDesign.brand,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  text.t(venue.address),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MapDesign.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContributionTextField extends StatelessWidget {
  const _ContributionTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.minLines = 1,
    this.maxLines = 1,
    this.onChanged,
  });

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
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      textInputAction: maxLines == 1
          ? TextInputAction.next
          : TextInputAction.newline,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 0),
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

class _ContributionImageSection extends StatelessWidget {
  const _ContributionImageSection({
    required this.title,
    required this.images,
    required this.imageCount,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final List<XFile> images;

  /// 店面与菜单共享的总张数上限，用于判断是否还能添加。
  final int imageCount;
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
      if (index == images.length && imageCount < 3) {
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
          height: slotSize,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            itemCount: slots.length,
            separatorBuilder: (_, _) => const SizedBox(width: gap),
            itemBuilder: (_, index) => slots[index],
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
        width: 104,
        height: 104,
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
      width: 104,
      height: 104,
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
            width: 104,
            height: 104,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const ColoredBox(
              color: Color(0xFFF7F2F5),
              child: SizedBox(
                width: 104,
                height: 104,
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
