import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/sipon_api_client.dart';
import '../services/sipon_api_service.dart';
import 'language_transform.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  static const int _maxImages = 3;
  static const int _maxUploadBytes = 10 * 1024 * 1024;
  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);
  static const Color _muted = Color(0xFF8E8790);
  static const Color _line = Color(0xFFF1EBEF);

  final SiponApiService _api = SiponApiService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _feedbackController = TextEditingController();

  final List<XFile> _selectedImages = <XFile>[];
  bool _submitting = false;

  List<dynamic> _history = <dynamic>[];
  bool _loadingHistory = false;
  bool _historyLoaded = false;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  /// 拉取当前用户的反馈历史列表。
  Future<void> _loadHistory() async {
    if (!mounted || _loadingHistory) return;
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final list = await _api.getMyFeedback();
      if (!mounted) return;
      setState(() {
        _history = List<dynamic>.from(list);
        _historyLoaded = true;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _historyError = _describeError(error);
        _historyLoaded = true;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingHistory = false);
      }
    }
  }

  /// 弹出图片来源选择面板并从相册/相机选择一张截图。
  Future<void> _showImageSourceSheet(SiponAppText text) async {
    if (_selectedImages.length >= _maxImages) {
      _showMessage(text.t('最多添加 3 张截图'));
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(
                text.t('选择图片来源'),
                style: const TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              _SourceOption(
                icon: Icons.photo_library_outlined,
                label: text.t('从相册选择'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
              _SourceOption(
                icon: Icons.photo_camera_outlined,
                label: text.t('拍照'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
    if (source == null) return;
    await _pickImage(text, source);
  }

  Future<void> _pickImage(SiponAppText text, ImageSource source) async {
    try {
      // maxWidth 与 imageQuality 会在 iOS/Android 上把超出尺寸的图片压缩为 JPEG，
      // 未超尺寸的原图保持原始格式，MIME 类型与文件签名仍一致。
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() => _selectedImages.add(file));
    } on Exception {
      if (!mounted) return;
      _showMessage(text.t('图片选择失败，请重试'));
    }
  }

  void _removeImage(int index) {
    setState(() => _selectedImages.removeAt(index));
  }

  /// 逐张上传截图到 /api/uploads，返回媒体 ID 列表；任意一张失败即抛错终止。
  Future<List<String>> _uploadImages() async {
    final mediaIds = <String>[];
    for (var index = 0; index < _selectedImages.length; index++) {
      final file = _selectedImages[index];
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxUploadBytes) {
        throw _FeedbackUploadException('图片超过 10MiB 限制，请更换图片');
      }
      final response = await _api.uploadMedia(
        fileBytes: bytes,
        filename: file.name,
        mimeType: _mimeTypeFor(file),
        purpose: 'feedback',
      );
      final mediaId = _extractMediaId(response);
      if (mediaId == null || mediaId.isEmpty) {
        throw _FeedbackUploadException('图片超过 10MiB 限制，请更换图片');
      }
      mediaIds.add(mediaId);
    }
    return mediaIds;
  }

  /// 提交反馈：先上传图片，再把内容与媒体 ID 一起 POST 到 /api/feedback。
  Future<void> _submitFeedback(SiponAppText text) async {
    final content = _feedbackController.text.trim();
    if (content.isEmpty) {
      _showMessage(text.feedbackRequired);
      return;
    }
    if (_submitting) return;

    setState(() => _submitting = true);
    FocusScope.of(context).unfocus();
    try {
      final mediaIds = await _uploadImages();
      await _api.createFeedback({
        'category': 'other',
        'content': content,
        if (mediaIds.isNotEmpty) 'mediaIds': mediaIds,
        'clientContext': _clientContext(),
      });
      if (!mounted) return;

      _feedbackController.clear();
      setState(() => _selectedImages.clear());
      _showMessage(text.feedbackSent);
      await _loadHistory();
    } on _FeedbackUploadException catch (error) {
      if (!mounted) return;
      _showMessage(text.t(error.message));
    } on SiponApiException {
      if (!mounted) return;
      _showMessage(text.t('提交失败，请稍后重试'));
    } on Exception {
      if (!mounted) return;
      _showMessage(text.t(_selectedImages.isEmpty
          ? '提交失败，请稍后重试'
          : '图片上传失败，请重试'));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// 组装客户端环境信息，随反馈一起上报，便于定位问题。
  Map<String, Object> _clientContext() {
    return {
      'platform': Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
              ? 'android'
              : 'other',
      'appVersion': '1.0.0',
      'osVersion': Platform.operatingSystemVersion,
    };
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

  String _describeError(Exception error) {
    if (error is SiponApiException) {
      final detail = error.message?.trim();
      if (detail != null && detail.isNotEmpty) return detail;
    }
    return error.toString();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFF2F3), Color(0xFFFCFCFC), Colors.white],
            stops: [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
                    sliver: SliverList.list(
                      children: [
                        _ReviewTopBar(
                          title: text.featureFeedback,
                          back: text.back,
                        ),
                        const SizedBox(height: 20),
                        _FeedbackSection(
                          text: text,
                          controller: _feedbackController,
                          images: _selectedImages,
                          submitting: _submitting,
                          onAddImage: () => _showImageSourceSheet(text),
                          onRemoveImage: _removeImage,
                          onSubmit: () => _submitFeedback(text),
                        ),
                        const SizedBox(height: 16),
                        _FeedbackHistorySection(
                          text: text,
                          records: _history,
                          loading: _loadingHistory,
                          loaded: _historyLoaded,
                          error: _historyError,
                          onRetry: _loadHistory,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 上传阶段的用户可读异常（如超过大小限制）。
class _FeedbackUploadException implements Exception {
  const _FeedbackUploadException(this.message);

  final String message;
}

/// 单条反馈历史记录的展示数据模型。
class _FeedbackRecord {
  const _FeedbackRecord({
    required this.content,
    this.id,
    this.category,
    this.createdAt,
    this.status,
    this.mediaIds = const [],
  });

  factory _FeedbackRecord.fromJson(Object? raw) {
    if (raw is! Map) {
      return const _FeedbackRecord(content: '');
    }
    final id = raw['id']?.toString();
    final content = raw['content']?.toString() ?? '';
    final category = raw['category']?.toString();
    final createdAt = DateTime.tryParse(raw['createdAt']?.toString() ?? '');
    final status = raw['status']?.toString();
    final mediaIds = <String>[];
    final rawMediaIds = raw['mediaIds'];
    if (rawMediaIds is List) {
      for (final item in rawMediaIds) {
        final idValue = item?.toString();
        if (idValue != null && idValue.isNotEmpty) mediaIds.add(idValue);
      }
    } else if (rawMediaIds is String && rawMediaIds.trim().isNotEmpty) {
      mediaIds.add(rawMediaIds.trim());
    }
    return _FeedbackRecord(
      id: id,
      content: content,
      category: category,
      createdAt: createdAt,
      status: status,
      mediaIds: mediaIds,
    );
  }

  final String? id;
  final String content;
  final String? category;
  final DateTime? createdAt;
  final String? status;
  final List<String> mediaIds;
}

class _ReviewTopBar extends StatelessWidget {
  const _ReviewTopBar({required this.title, required this.back});

  final String title;
  final String back;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Tooltip(
            message: back,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: IconButton.styleFrom(
                fixedSize: const Size(40, 40),
                backgroundColor: Colors.white.withValues(alpha: 0.78),
                foregroundColor: _ReviewPageState._ink,
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ReviewPageState._ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: _ReviewPageState._brand),
      title: Text(
        label,
        style: const TextStyle(
          color: _ReviewPageState._ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _FeedbackSection extends StatelessWidget {
  const _FeedbackSection({
    required this.text,
    required this.controller,
    required this.images,
    required this.submitting,
    required this.onAddImage,
    required this.onRemoveImage,
    required this.onSubmit,
  });

  final SiponAppText text;
  final TextEditingController controller;
  final List<XFile> images;
  final bool submitting;
  final VoidCallback onAddImage;
  final ValueChanged<int> onRemoveImage;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.add_comment_outlined,
            title: text.t('留言反馈'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: text.feedbackHint,
              filled: true,
              fillColor: const Color(0xFFFCF8FA),
              contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _ReviewPageState._line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: _ReviewPageState._brand,
                  width: 1.3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _ImagePickerSection(
            text: text,
            images: images,
            onAdd: onAddImage,
            onRemove: onRemoveImage,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: submitting ? null : onSubmit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                backgroundColor: _ReviewPageState._brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE6D3DF),
                disabledForegroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.post_add_rounded, size: 18),
              label: Text(
                submitting ? text.t('提交中...') : text.submitFeedback,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImagePickerSection extends StatelessWidget {
  const _ImagePickerSection({
    required this.text,
    required this.images,
    required this.onAdd,
    required this.onRemove,
  });

  final SiponAppText text;
  final List<XFile> images;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.t('添加图片'),
          style: const TextStyle(
            color: _ReviewPageState._ink,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var index = 0; index < images.length; index++)
              _ImageTile(file: images[index], onRemove: () => onRemove(index)),
            if (images.length < 3) _AddImageTile(text: text, onTap: onAdd),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          text.t('最多上传 3 张问题截图，便于我们定位页面和异常。'),
          style: const TextStyle(
            color: _ReviewPageState._muted,
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.file, required this.onRemove});

  final XFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(file.path),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFFFFF6FB),
                    ),
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: _ReviewPageState._brand,
                      size: 26,
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            right: -6,
            top: -6,
            child: IconButton.filled(
              onPressed: onRemove,
              style: IconButton.styleFrom(
                fixedSize: const Size(24, 24),
                padding: EdgeInsets.zero,
                backgroundColor: _ReviewPageState._ink,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.close_rounded, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddImageTile extends StatelessWidget {
  const _AddImageTile({required this.text, required this.onTap});

  final SiponAppText text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: const Color(0xFFFCF8FA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _ReviewPageState._line),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.add_photo_alternate_outlined,
                color: _ReviewPageState._brand,
                size: 26,
              ),
              const SizedBox(height: 6),
              Text(
                text.t('添加'),
                style: const TextStyle(
                  color: _ReviewPageState._brand,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedbackHistorySection extends StatelessWidget {
  const _FeedbackHistorySection({
    required this.text,
    required this.records,
    required this.loading,
    required this.loaded,
    required this.error,
    required this.onRetry,
  });

  final SiponAppText text;
  final List<dynamic> records;
  final bool loading;
  final bool loaded;
  final String? error;
  final VoidCallback onRetry;

  /// 把后端 category 枚举映射为可读文案。
  String _categoryLabel(String? category) {
    switch (category) {
      case 'feature_request':
        return text.t('功能建议');
      case 'bug':
        return text.t('问题反馈');
      default:
        return text.t('其他');
    }
  }

  String _statusLabel(String? status) {
    if (status == null || status == 'pending' || status == 'processing') {
      return text.t('处理中');
    }
    return text.t('已处理');
  }

  String _formatTime(DateTime? time) {
    final value = time;
    if (value == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.history_rounded,
            title: text.t('历史反馈'),
          ),
          const SizedBox(height: 4),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: _ReviewPageState._brand,
                  ),
                ),
              ),
            )
          else if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      text.t('历史反馈加载失败'),
                      style: const TextStyle(
                        color: _ReviewPageState._muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onRetry,
                      child: Text(
                        text.t('重新加载'),
                        style: const TextStyle(
                          color: _ReviewPageState._brand,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (!loaded)
            const SizedBox.shrink()
          else if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  text.t('暂无反馈记录'),
                  style: const TextStyle(
                    color: _ReviewPageState._muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [
                  for (var index = 0; index < records.length; index++) ...[
                    _FeedbackHistoryItem(
                      text: text,
                      record: _FeedbackRecord.fromJson(records[index]),
                      categoryLabel: _categoryLabel,
                      statusLabel: _statusLabel,
                      time: _formatTime,
                    ),
                    if (index != records.length - 1)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedbackHistoryItem extends StatelessWidget {
  const _FeedbackHistoryItem({
    required this.text,
    required this.record,
    required this.categoryLabel,
    required this.statusLabel,
    required this.time,
  });

  final SiponAppText text;
  final _FeedbackRecord record;
  final String Function(String?) categoryLabel;
  final String Function(String?) statusLabel;
  final String Function(DateTime?) time;

  @override
  Widget build(BuildContext context) {
    final createdAt = time(record.createdAt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _ReviewPageState._line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                categoryLabel(record.category),
                style: const TextStyle(
                  color: _ReviewPageState._brand,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEDF7),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  statusLabel(record.status),
                  style: const TextStyle(
                    color: _ReviewPageState._brand,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          if (createdAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              createdAt,
              style: const TextStyle(
                color: _ReviewPageState._muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            record.content,
            style: const TextStyle(
              color: _ReviewPageState._ink,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          if (record.mediaIds.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.photo_library_outlined,
                  color: _ReviewPageState._brand,
                  size: 16,
                ),
                const SizedBox(width: 5),
                Text(
                  text.t('已附带 ${record.mediaIds.length} 张图片'),
                  style: const TextStyle(
                    color: _ReviewPageState._brand,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F9A3D78),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 17),
        child: child,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEDF7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _ReviewPageState._brand, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ReviewPageState._ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}