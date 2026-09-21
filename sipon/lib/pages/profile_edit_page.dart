import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../services/sipon_api_client.dart';
import '../services/sipon_api_service.dart';
import '../services/user_profile_data.dart';
import '../widgets/sipon_network_image.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key, required this.profile});

  final UserProfileData profile;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _api = SiponApiService();
  final ImagePicker _picker = ImagePicker();
  // 与公开主页一致的默认头像占位图。
  static const String _avatarAsset = 'assest/首页/图片素材/Bharat Balami.png';
  static const int _maxAvatarBytes = 10 * 1024 * 1024;
  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);
  static const Color _line = Color(0xFFF1EBEF);
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _cityController;
  late final TextEditingController _avatarController;
  XFile? _pickedAvatar;
  bool _saving = false;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.displayName);
    _bioController = TextEditingController(text: widget.profile.bio);
    _cityController = TextEditingController(text: widget.profile.city);
    _avatarController = TextEditingController(text: widget.profile.avatarUrl);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _cityController.dispose();
    _avatarController.dispose();
    super.dispose();
  }

  // ---- 头像编辑：选图 → 上传 /api/uploads → 回填 avatarUrl ----

  Future<void> _changeAvatar() async {
    if (_uploadingAvatar || _saving) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    XFile? file;
    try {
      // maxWidth 与 imageQuality 在 iOS/Android 上会把超尺寸图片压缩为
      // JPEG，未超尺寸的原图保持原始格式，MIME 类型仍按扩展名兜底推断。
      file = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        imageQuality: 85,
      );
    } on Exception {
      if (mounted) _showMessage('图片选择失败，请重试');
      return;
    }
    if (file == null || !mounted) return;
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '裁切头像',
            lockAspectRatio: true,
            hideBottomControls: true,
          ),
          IOSUiSettings(
            title: '裁切头像',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );
      // 用户取消裁切时不更改当前头像，也不发起上传。
      if (cropped == null || !mounted) return;
      file = XFile(cropped.path, name: 'avatar.jpg', mimeType: 'image/jpeg');
    } on MissingPluginException {
      // 新增原生插件后，Hot Reload/Hot Restart 不会注册插件；必须完整重启应用。
      if (mounted) {
        _showMessage('图片裁切组件尚未加载，请完全停止应用后重新运行');
      }
      return;
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(
          error.message?.trim().isNotEmpty == true
              ? '图片裁切失败：${error.message}'
              : '图片裁切失败，请重试',
        );
      }
      return;
    } on Exception {
      if (mounted) _showMessage('图片裁切失败，请重试');
      return;
    }
    setState(() {
      _pickedAvatar = file;
      _uploadingAvatar = true;
    });
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > _maxAvatarBytes) {
        throw const FormatException('图片超过 10MiB 限制，请更换图片');
      }
      final response = await _api.uploadMedia(
        fileBytes: bytes,
        filename: file.name,
        mimeType: _mimeTypeFor(file),
        purpose: 'avatar',
        purposeInQuery: true,
      );
      debugPrint('Avatar upload response: $response');
      final mediaId = _extractMediaId(response);
      if (mediaId == null) {
        debugPrint('Avatar upload returned no media ID: $response');
        throw const FormatException('上传成功但服务端未返回媒体 ID');
      }
      if (!mounted) return;
      setState(() {
        _avatarController.text = _avatarUrlFromUpload(response, mediaId);
      });
      _showMessage('头像已上传，请点击保存资料');
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _pickedAvatar = null);
      _showMessage(error.message);
    } on SiponApiException catch (error) {
      if (!mounted) return;
      setState(() => _pickedAvatar = null);
      debugPrint(
        'Avatar upload failed: status=${error.statusCode}, '
        'code=${error.code}, path=${error.path}, '
        'requestId=${error.requestId}, message=${error.message}',
      );
      _showMessage(
        '上传失败（${error.statusCode}）：${_compactErrorMessage(error.message ?? '')}',
      );
    } on Exception catch (error, stackTrace) {
      if (!mounted) return;
      setState(() => _pickedAvatar = null);
      debugPrint('Avatar upload failed: $error\n$stackTrace');
      _showMessage('头像上传失败，请重试');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  /// 从上传响应的多种字段名中尽力提取媒体 ID。
  String? _extractMediaId(dynamic response) {
    if (response is! Map) return null;
    final raw =
        response['mediaId'] ??
        response['id'] ??
        (response['data'] is Map
            ? (response['data']['mediaId'] ?? response['data']['id'])
            : null);
    final id = raw?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// 资料接口会校验上传归属，必须提交上传接口原样返回的相对内容路径。
  String _avatarUrlFromUpload(dynamic response, String mediaId) {
    String? url;
    if (response is Map) {
      final raw =
          response['url'] ??
          (response['data'] is Map ? response['data']['url'] : null);
      url = raw?.toString().trim();
    }
    return url?.isNotEmpty == true
        ? url!
        : '/api/uploads/${Uri.encodeComponent(mediaId)}/content';
  }

  String _compactErrorMessage(String message) {
    final normalized = message.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return '请稍后重试';
    return normalized.length <= 80
        ? normalized
        : '${normalized.substring(0, 80)}…';
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildAvatarEditor() {
    return Center(
      child: GestureDetector(
        onTap: _changeAvatar,
        child: Stack(
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: _brand.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipOval(child: _buildAvatarImage()),
            ),
            if (_uploadingAvatar)
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black38,
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFB4528F), _brand],
                  ),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _brand.withValues(alpha: 0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.photo_camera_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarImage() {
    final picked = _pickedAvatar;
    if (picked != null) {
      return Image.file(File(picked.path), fit: BoxFit.cover);
    }
    final url = _avatarController.text.trim();
    if (url.isNotEmpty) {
      return SiponNetworkImage(
        url: url,
        fallbackAsset: _avatarAsset,
        auth: true,
      );
    }
    return Image.asset(_avatarAsset, fit: BoxFit.cover);
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final name = _nameController.text.trim();
    final avatar = _nullableValue(_avatarController.text);
    // 按用户资料接口约定提交字段，避免未定义别名被后端静默忽略。
    final body = <String, Object?>{
      'displayName': name,
      'bio': _nullableValue(_bioController.text),
      'city': _nullableValue(_cityController.text),
      'avatarUrl': avatar,
    };
    try {
      debugPrint('Profile save request: $body');
      final response = await _api.updateMyProfile(body);
      debugPrint('Profile save response: $response');
      if (!mounted) return;
      // 有些 PATCH 实现返回 204 或仅返回变更字段；用提交值补齐展示资料。
      final returnedFields = response is Map
          ? response.map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            )
          : const <String, Object?>{};
      final updated = UserProfileData.fromJson({
        ..._profileJson(),
        ...body,
        ...returnedFields,
      });
      _showMessage('资料已保存');
      Navigator.of(context).pop(updated);
    } on SiponApiException catch (error) {
      if (!mounted) return;
      debugPrint(
        'Profile save failed: status=${error.statusCode}, '
        'requestId=${error.requestId}, message=${error.message}',
      );
      _showMessage(
        '保存失败（${error.statusCode}）：${_compactErrorMessage(error.message ?? '')}',
      );
    } on Exception catch (error, stackTrace) {
      if (!mounted) return;
      debugPrint('Profile save failed: $error\n$stackTrace');
      _showMessage('保存失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, Object?> _profileJson() => {
    'id': widget.profile.id,
    'username': widget.profile.username,
    'email': widget.profile.email,
    'displayName': widget.profile.displayName,
    'avatarUrl': widget.profile.avatarUrl,
    'bio': widget.profile.bio,
    'city': widget.profile.city,
    'level': widget.profile.level,
    'locale': widget.profile.locale,
  };

  String? _nullableValue(String input) {
    final value = input.trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          '编辑资料',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _ink),
      ),
      body: DecoratedBox(
        // 与全站页面一致的浅粉渐变背景。
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFF2F3), Color(0xFFFCFCFC), Colors.white],
            stops: [0, 0.45, 1],
          ),
        ),
        child: SafeArea(
          // bottom:false 让滚动视口延伸到屏幕底，可滚过小白条区域；
          // 底部空间由 ListView 的 padding 预留。
          bottom: false,
          child: Form(
            key: _formKey,
            child: ListView(
              // 底部预留系统安全区（Home Indicator）。
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                const SizedBox(height: 8),
                _buildAvatarEditor(),
                const SizedBox(height: 10),
                Text(
                  _uploadingAvatar ? '头像上传中…' : '点击更换头像',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _brand,
                  ),
                ),
                const SizedBox(height: 24),
                const _EditHint('头像、昵称、简介和所在城市会展示在你的公开主页；邮箱和账号 ID 不会在这里修改。'),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _brand.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ProfileField(
                        controller: _nameController,
                        label: '昵称',
                        hint: '输入展示昵称',
                        maxLength: 40,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? '请输入昵称'
                            : null,
                      ),
                      const Divider(height: 1, color: _line),
                      _ProfileField(
                        controller: _bioController,
                        label: '个人简介',
                        hint: '介绍一下自己',
                        maxLength: 160,
                        maxLines: 4,
                      ),
                      const Divider(height: 1, color: _line),
                      _ProfileField(
                        controller: _cityController,
                        label: '所在城市',
                        hint: '例如：上海',
                        maxLength: 40,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                _buildSaveButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    final enabled = !_saving && !_uploadingAvatar;
    return Opacity(
      opacity: enabled ? 1 : 0.7,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFB4528F), _brand],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _brand.withValues(alpha: 0.32),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FilledButton(
          onPressed: enabled ? _save : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Text(
                  '保存资料',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}

class _EditHint extends StatelessWidget {
  const _EditHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF2F7),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFF6DFEA)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: Color(0xFF9A3D78),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF6D5E67),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLength,
    this.maxLines = 1,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int? maxLength;
  final int maxLines;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      // 基线对齐：标签与输入区第一行文字（含占位提示）始终在同一水平线上。
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF292B32),
            ),
          ),
        ),
        Expanded(
          child: TextFormField(
            controller: controller,
            validator: validator,
            maxLength: maxLength,
            maxLines: maxLines,
            textAlign: TextAlign.start,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF292B32),
            ),
            // 仅在聚焦时显示字数统计，保持列表整洁。
            buildCounter:
                (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) {
                  if (!isFocused || maxLength == null) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    '$currentLength/$maxLength',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8E8790),
                    ),
                  );
                },
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: Color(0xFFC4BCC3),
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              counterText: '',
            ),
          ),
        ),
      ],
    ),
  );
}
