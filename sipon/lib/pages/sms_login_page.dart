import 'package:flutter/material.dart';

import '../services/sipon_api_client.dart';
import '../services/sipon_auth_service.dart';
import 'language_transform.dart';

const siponLoginLogoHeroTag = 'sipon-login-logo';

class SmsLoginPage extends StatefulWidget {
  const SmsLoginPage({super.key, required this.onLoginSucceeded});

  final VoidCallback onLoginSucceeded;

  @override
  State<SmsLoginPage> createState() => _SmsLoginPageState();
}

class _SmsLoginPageState extends State<SmsLoginPage> {
  static const _brand = Color(0xFF9A3D78);
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = SiponAuthService.instance;
  bool _submitting = false;
  bool _obscurePassword = true;

  bool get _canSubmit =>
      _usernameController.text.trim().isNotEmpty &&
      _passwordController.text.length >= 6 &&
      !_submitting;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_canSubmit) return;
    await _runAuthAction(
      () => _authService.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      ),
      successMessage: null,
    );
  }

  Future<void> _runAuthAction(
    Future<void> Function() action, {
    required String? successMessage,
  }) async {
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await action();
      if (!mounted) return;
      if (successMessage != null) _showMessage(successMessage);
      widget.onLoginSucceeded();
    } catch (error) {
      _showMessage(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _errorMessage(Object error) {
    final text = SiponLanguageScope.textOf(context);
    if (error is SiponApiException) {
      final message = error.message?.trim();
      if (message != null && message.isNotEmpty) return message;
      return text.t('请求失败，请稍后重试。');
    }
    if (error is SiponAuthException) return text.t(error.message);
    return text.t('网络异常，请检查网络和服务地址。');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    final languageController = SiponLanguageScope.controllerOf(context);
    final text = SiponLanguageScope.textOf(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 12,
              right: 20,
              child: _LoginLanguageSwitch(
                text: text,
                language: languageController.language,
                onChanged: languageController.setLanguage,
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 34, 28, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Column(
                          children: [
                            Hero(
                              tag: siponLoginLogoHeroTag,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.asset(
                                  'assest/logo.png',
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              text.t('欢迎来到 SipOn'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF292B32),
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              text.t('记录每一次微醺。'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF8E8790),
                                fontSize: 14,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 42),
                      Text(
                        text.t('用户名'),
                        style: const TextStyle(
                          color: Color(0xFF292B32),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 9),
                      _inputField(
                        controller: _usernameController,
                        hint: text.t('请输入用户名'),
                        icon: Icons.person_outline_rounded,
                        obscureText: false,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 22),
                      Text(
                        text.t('密码'),
                        style: const TextStyle(
                          color: Color(0xFF292B32),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 9),
                      _inputField(
                        controller: _passwordController,
                        hint: text.t('请输入密码（至少 6 位）'),
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _login(),
                        suffixIcon: IconButton(
                          tooltip: text.t(_obscurePassword ? '显示密码' : '隐藏密码'),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _canSubmit ? _login : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: _brand,
                            disabledBackgroundColor: const Color(0xFFE9D8E2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  text.t('登录'),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Text(
                          text.t('登录即代表你已阅读并同意用户协议和隐私政策'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFAAA2A8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool obscureText,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 21, color: const Color(0xFF8E8790)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE9E3E7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE9E3E7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _brand, width: 1.4),
        ),
      ),
    );
  }
}

class _LoginLanguageSwitch extends StatelessWidget {
  const _LoginLanguageSwitch({
    required this.text,
    required this.language,
    required this.onChanged,
  });

  final SiponAppText text;
  final SiponLanguage language;
  final ValueChanged<SiponLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE9E3E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LoginLanguageOption(
              label: text.languageChinese,
              selected: language == SiponLanguage.zh,
              onTap: () => onChanged(SiponLanguage.zh),
            ),
            _LoginLanguageOption(
              label: text.languageEnglish,
              selected: language == SiponLanguage.en,
              onTap: () => onChanged(SiponLanguage.en),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginLanguageOption extends StatelessWidget {
  const _LoginLanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: selected ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? _SmsLoginPageState._brand : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : const Color(0xFF8E8790),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
