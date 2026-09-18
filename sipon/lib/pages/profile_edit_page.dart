import 'package:flutter/material.dart';

import '../services/sipon_api_service.dart';
import '../services/user_profile_data.dart';

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({super.key, required this.profile});

  final UserProfileData profile;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _api = SiponApiService();
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _cityController;
  late final TextEditingController _avatarController;
  bool _saving = false;

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

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final body = <String, Object?>{
      'displayName': _nameController.text.trim(),
      'bio': _nullableValue(_bioController.text),
      'city': _nullableValue(_cityController.text),
      'avatarUrl': _nullableValue(_avatarController.text),
    };
    try {
      final response = await _api.updateMyProfile(body);
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
      Navigator.of(context).pop(updated);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试。')));
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
      appBar: AppBar(
        title: const Text('编辑资料'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _EditHint('头像、昵称、简介和所在城市会展示在你的公开主页；邮箱和账号 ID 不会在这里修改。'),
              const SizedBox(height: 20),
              _ProfileField(
                controller: _nameController,
                label: '昵称',
                hint: '输入展示昵称',
                maxLength: 40,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '请输入昵称' : null,
              ),
              _ProfileField(
                controller: _bioController,
                label: '个人简介',
                hint: '介绍一下自己',
                maxLength: 160,
                maxLines: 4,
              ),
              _ProfileField(
                controller: _cityController,
                label: '所在城市',
                hint: '例如：上海',
                maxLength: 40,
              ),
              _ProfileField(
                controller: _avatarController,
                label: '头像链接',
                hint: 'https://… 或后端返回的资源路径',
                keyboardType: TextInputType.url,
                validator: (value) {
                  final url = value?.trim() ?? '';
                  if (url.isEmpty || url.startsWith('/')) return null;
                  final uri = Uri.tryParse(url);
                  return uri?.hasScheme == true ? null : '请输入有效的图片链接';
                },
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: const Color(0xFF9A3D78),
                ),
                child: Text(_saving ? '保存中…' : '保存资料'),
              ),
            ],
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
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF2F7),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: const TextStyle(color: Color(0xFF6D5E67))),
  );
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.controller,
    required this.label,
    required this.hint,
    this.maxLength,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int? maxLength;
  final int maxLines;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: TextFormField(
      controller: controller,
      validator: validator,
      maxLength: maxLength,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: maxLines > 1,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
