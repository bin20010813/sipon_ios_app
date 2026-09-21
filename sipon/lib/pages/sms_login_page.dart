import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../services/sipon_agreement_links.dart';
import '../services/sipon_api_client.dart';
import '../services/sipon_auth_service.dart';
import 'language_transform.dart';

const siponLoginLogoHeroTag = 'sipon-login-logo';

/// 登录界面内的两种方式：密码登录 / 验证码登录。
enum _LoginMethod { password, code }

/// 认证页面的三种视图：登录 / 注册 / 重置密码。
enum _AuthPage { login, register, reset }

class SmsLoginPage extends StatefulWidget {
  const SmsLoginPage({super.key, required this.onLoginSucceeded});

  final VoidCallback onLoginSucceeded;

  @override
  State<SmsLoginPage> createState() => _SmsLoginPageState();
}

class _SmsLoginPageState extends State<SmsLoginPage> {
  static const _brand = Color(0xFF9A3D78);
  static const _codeCooldownSeconds = 60;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  final _authService = SiponAuthService.instance;
  late final TapGestureRecognizer _userAgreementRecognizer;
  late final TapGestureRecognizer _privacyPolicyRecognizer;
  _LoginMethod _method = _LoginMethod.password;

  /// 当前认证视图（登录/注册/重置密码）。
  _AuthPage _page = _AuthPage.login;
  bool _submitting = false;
  bool _appleSubmitting = false;
  bool _sendingCode = false;
  bool _obscurePassword = true;
  bool _agreed = false;
  Timer? _codeTimer;
  int _codeCountdown = 0;

  /// 当前视图是否可以提交。
  bool get _canSubmit {
    if (_emailController.text.trim().isEmpty || _submitting) return false;
    if (_page != _AuthPage.login) {
      return _codeController.text.trim().length == 6 &&
          _passwordController.text.length >= 8;
    }
    switch (_method) {
      case _LoginMethod.password:
        return _passwordController.text.length >= 6;
      case _LoginMethod.code:
        return _codeController.text.trim().length == 6;
    }
  }

  /// 切换认证视图（登录/注册/重置密码）时重置表单与倒计时，避免窜数据。
  void _switchPage(_AuthPage page) {
    setState(() {
      _page = page;
      _codeController.clear();
      _passwordController.clear();
      _obscurePassword = true;
      _codeTimer?.cancel();
      _codeCountdown = 0;
    });
  }

  @override
  void initState() {
    super.initState();
    _userAgreementRecognizer = TapGestureRecognizer()
      ..onTap = () => _openAgreement(kSiponUserAgreementUrl);
    _privacyPolicyRecognizer = TapGestureRecognizer()
      ..onTap = () => _openAgreement(kSiponPrivacyPolicyUrl);
  }

  @override
  void dispose() {
    _codeTimer?.cancel();
    _userAgreementRecognizer.dispose();
    _privacyPolicyRecognizer.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// 在系统浏览器中打开指定协议官网地址，失败时给出提示。
  Future<void> _openAgreement(String url) async {
    final opened = await openAgreementInBrowser(url);
    if (!opened && mounted) {
      _showMessage(SiponLanguageScope.textOf(context).t('无法打开链接，请稍后重试。'));
    }
  }

  /// 未勾选协议时，弹出阅读协议确认弹窗，返回用户是否选择同意。
  Future<bool> _confirmAgreement() async {
    final text = SiponLanguageScope.textOf(context);
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(text.t('阅读并同意协议')),
          content: Text.rich(
            TextSpan(
              text: text.t('请阅读并同意'),
              style: const TextStyle(
                color: Color(0xFF5C565D),
                fontSize: 14,
                height: 1.6,
              ),
              children: [
                TextSpan(
                  text: text.t('用户协议'),
                  style: const TextStyle(
                    color: _brand,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  recognizer: _userAgreementRecognizer,
                ),
                TextSpan(text: text.t('和')),
                TextSpan(
                  text: text.t('隐私政策'),
                  style: const TextStyle(
                    color: _brand,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                  recognizer: _privacyPolicyRecognizer,
                ),
                TextSpan(text: text.t('，点击协议名称可查看完整内容。')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(text.t('不同意')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: _brand,
                foregroundColor: Colors.white,
              ),
              child: Text(text.t('同意并继续')),
            ),
          ],
        );
      },
    );

    return agreed == true;
  }

  /// 邮箱基本格式校验（含 @ 且点在 @ 之后）。
  bool _isValidEmail(String email) {
    final at = email.indexOf('@');
    return at > 0 && email.indexOf('.', at) > at + 1;
  }

  /// 仅 Apple 平台支持 Sign in with Apple。
  bool get _supportsAppleSignIn =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// 调起 Apple 授权并换取登录态。
  Future<void> _loginWithApple() async {
    final text = SiponLanguageScope.textOf(context);

    if (!_agreed) {
      final agreed = await _confirmAgreement();
      if (!mounted || !agreed) return;
      setState(() => _agreed = true);
    }

    FocusScope.of(context).unfocus();
    setState(() => _appleSubmitting = true);
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final identityToken = credential.identityToken;
      if (identityToken == null || identityToken.isEmpty) {
        if (mounted) _showMessage(text.t('Apple 登录失败，请重试'));
        return;
      }
      await _authService.loginWithApple(
        identityToken: identityToken,
        authorizationCode: credential.authorizationCode,
        displayName: _joinName(credential.givenName, credential.familyName),
      );
      if (!mounted) return;
      widget.onLoginSucceeded();
    } on SignInWithAppleException catch (error) {
      // 用户主动取消属于正常流程，不提示错误。
      if (error.code == AuthorizationErrorCode.canceled) return;
      if (mounted) _showMessage(text.t('Apple 登录失败，请重试'));
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _appleSubmitting = false);
    }
  }

  /// 拼装 Apple 授权返回的姓名；为空则返回 null。
  String? _joinName(String? given, String? family) {
    final givenName = given?.trim();
    final familyName = family?.trim();
    if (givenName == null || givenName.isEmpty) return null;
    if (familyName == null || familyName.isEmpty) return givenName;
    return '$givenName $familyName';
  }

  /// 提交当前界面动作：登录（密码/验证码）或注册。
  Future<void> _submit() async {
    if (!_canSubmit) return;

    if (!_agreed) {
      final agreed = await _confirmAgreement();
      if (!mounted || !agreed) return;
      setState(() => _agreed = true);
    }

    final email = _emailController.text.trim();
    final text = SiponLanguageScope.textOf(context);
    if (!_isValidEmail(email)) {
      _showMessage(text.t('请填写正确的邮箱地址'));
      return;
    }

    Future<void> action;
    switch (_page) {
      case _AuthPage.login:
        switch (_method) {
          case _LoginMethod.password:
            action = _authService.emailPasswordLogin(
              email: email,
              password: _passwordController.text,
            );
          case _LoginMethod.code:
            action = _authService.emailLogin(
              email: email,
              code: _codeController.text.trim(),
            );
        }
      case _AuthPage.register:
        action = _authService.emailRegister(
          email: email,
          code: _codeController.text.trim(),
          password: _passwordController.text,
        );
      case _AuthPage.reset:
        action = _authService.resetEmailPassword(
          email: email,
          code: _codeController.text.trim(),
          newPassword: _passwordController.text,
        );
    }

    await _runAuthAction(
      () => action,
      successMessage: switch (_page) {
        _AuthPage.register => text.t('注册成功'),
        _AuthPage.reset => text.t('密码已重置，请重新登录'),
        _AuthPage.login => null,
      },
    );
    // 重置成功（未登录）后切回登录视图，方便直接用新密码登录。
    if (mounted && _page == _AuthPage.reset) {
      _switchPage(_AuthPage.login);
    }
  }

  /// 请求发送验证码：校验邮箱后调后端，成功后进入 60s 倒计时。
  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    final text = SiponLanguageScope.textOf(context);
    if (email.isEmpty || !_isValidEmail(email)) {
      _showMessage(text.t('请填写正确的邮箱地址'));
      return;
    }
    if (_sendingCode || _codeCountdown > 0) return;

    setState(() => _sendingCode = true);
    try {
      await _authService.requestEmailCode(email);
      if (!mounted) return;
      _showMessage(text.t('验证码已发送，请查收邮箱'));
      setState(() {
        _codeCountdown = _codeCooldownSeconds;
        _codeTimer?.cancel();
        _codeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_codeCountdown <= 1) {
            timer.cancel();
            if (mounted) {
              setState(() => _codeCountdown = 0);
            }
          } else if (mounted) {
            setState(() => _codeCountdown -= 1);
          }
        });
      });
    } on Exception {
      if (!mounted) return;
      _showMessage(text.t('验证码发送失败，请稍后重试'));
    } finally {
      if (mounted) {
        setState(() => _sendingCode = false);
      }
    }
  }

  /// 统一执行认证动作：成功回调登入，失败按异常类型提示。
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
        // bottom:false 让滚动视口延伸到屏幕底，可滚过小白条区域；
        // 底部空间由 SingleChildScrollView 的 padding 预留。
        bottom: false,
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
                  // 底部预留系统安全区（Home Indicator）。
                  padding: EdgeInsets.fromLTRB(
                    28,
                    34,
                    28,
                    28 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            const SizedBox(
                              width: 220,
                              child: Column(
                                children: [
                                  Text(
                                    'Turn the SIP ON',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF292B32),
                                      fontFamily: 'Dubai',
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                      height: 1,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '开饮   就现在',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF292B32),
                                      fontFamily: 'Microsoft YaHei',
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 4.1,
                                      height: 1.15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 34),
                      Text(
                        text.t(
                          switch (_page) {
                            _AuthPage.login => '登录',
                            _AuthPage.register => '注册',
                            _AuthPage.reset => '重置密码',
                          },
                        ),
                        style: const TextStyle(
                          color: Color(0xFF292B32),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        text.t('邮箱'),
                        style: const TextStyle(
                          color: Color(0xFF292B32),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 9),
                      _inputField(
                        controller: _emailController,
                        hint: text.t('请输入邮箱'),
                        icon: Icons.mail_outline_rounded,
                        obscureText: false,
                        textInputAction: TextInputAction.next,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 22),
                      if (_page != _AuthPage.login ||
                          _method == _LoginMethod.code) ...[
                        _FieldLabelRow(
                          label: text.t('验证码'),
                          actionLabel: _page == _AuthPage.login
                              ? text.t('密码登录')
                              : null,
                          actionIcon: _page == _AuthPage.login
                              ? Icons.lock_outline_rounded
                              : null,
                          onAction: () =>
                              setState(() => _method = _LoginMethod.password),
                        ),
                        const SizedBox(height: 9),
                        _codeField(text),
                        const SizedBox(height: 22),
                      ],
                      if (_page != _AuthPage.login ||
                          _method == _LoginMethod.password) ...[
                        _FieldLabelRow(
                          label: text.t('密码'),
                          actionLabel: _page == _AuthPage.login
                              ? text.t('验证码登录')
                              : null,
                          actionIcon: _page == _AuthPage.login
                              ? Icons.email_outlined
                              : null,
                          onAction: () =>
                              setState(() => _method = _LoginMethod.code),
                        ),
                        const SizedBox(height: 9),
                        _passwordField(text),
                        // 忘记密码入口放在密码框右下角，仅登录·密码模式展示。
                        if (_page == _AuthPage.login &&
                            _method == _LoginMethod.password) ...[
                          const SizedBox(height: 2),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _switchPage(_AuthPage.reset),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF8E8790),
                                minimumSize: const Size(0, 30),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: Text(text.t('忘记密码？')),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 14),
                      _buildAgreementCheckboxRow(text),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _canSubmit ? _submit : null,
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
                                  text.t(
                                    switch (_page) {
                                      _AuthPage.login => '登录',
                                      _AuthPage.register => '注册',
                                      _AuthPage.reset => '重置密码',
                                    },
                                  ),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      if (_page == _AuthPage.login &&
                          _supportsAppleSignIn) ...[
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                text.t('或'),
                                style: const TextStyle(
                                  color: Color(0xFFAAA3AA),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton.icon(
                            onPressed: _submitting || _appleSubmitting
                                ? null
                                : _loginWithApple,
                            icon: const Icon(Icons.apple, size: 24),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF292B32),
                              side: const BorderSide(
                                color: Color(0xFFE9E3E7),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            label: Text(
                              _appleSubmitting
                                  ? text.t('登录中…')
                                  : text.t('使用 Apple 登录'),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: () => _switchPage(
                            _page == _AuthPage.login
                                ? _AuthPage.register
                                : _AuthPage.login,
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: _brand,
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Text(
                            text.t(
                              switch (_page) {
                                _AuthPage.login => '还没有账号？立即注册',
                                _AuthPage.register => '已有账号？去登录',
                                _AuthPage.reset => '返回登录',
                              },
                            ),
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

  /// 验证码输入行：6 位数字 + 右侧获取/重发按钮（带倒计时）。
  Widget _codeField(SiponAppText text) {
    return Row(
      children: [
        Expanded(
          child: _inputField(
            controller: _codeController,
            hint: text.t('请输入验证码'),
            icon: Icons.shield_outlined,
            obscureText: false,
            maxLength: 6,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: _sendingCode || _codeCountdown > 0 ? null : _sendCode,
            style: OutlinedButton.styleFrom(
              foregroundColor: _brand,
              side: const BorderSide(color: _brand),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Text(
              _codeCountdown > 0
                  ? '$_codeCountdown s'
                  : text.t(_sendingCode ? '发送中…' : '获取验证码'),
            ),
          ),
        ),
      ],
    );
  }

  /// 密码输入行：默认隐藏明文，右上角可切换。
  Widget _passwordField(SiponAppText text) {
    return _inputField(
      controller: _passwordController,
      hint: text.t(
        _page == _AuthPage.login ? '请输入密码（至少 6 位）' : '请输入密码（至少 8 位）',
      ),
      icon: Icons.lock_outline_rounded,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      suffixIcon: IconButton(
        tooltip: text.t(_obscurePassword ? '显示密码' : '隐藏密码'),
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        icon: Icon(
          _obscurePassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          size: 20,
        ),
      ),
    );
  }

  /// 构建协议勾选行：勾选框 + 可点击的《用户协议》《隐私政策》链接。
  Widget _buildAgreementCheckboxRow(SiponAppText text) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _agreed = !_agreed),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: _agreed,
              onChanged: (value) => setState(() => _agreed = value ?? false),
              fillColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? _brand
                    : Colors.white,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              side: const BorderSide(color: Color(0xFFD5CDD2), width: 1.4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: text.t('我已阅读并同意'),
                style: const TextStyle(
                  color: Color(0xFF8E8790),
                  fontSize: 12,
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: text.t('用户协议'),
                    style: const TextStyle(
                      color: _brand,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    recognizer: _userAgreementRecognizer,
                  ),
                  TextSpan(text: text.t('和')),
                  TextSpan(
                    text: text.t('隐私政策'),
                    style: const TextStyle(
                      color: _brand,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    recognizer: _privacyPolicyRecognizer,
                  ),
                ],
              ),
            ),
          ),
        ],
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
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      keyboardType: keyboardType,
      maxLength: maxLength,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFAAA3AA)),
        prefixIcon: Icon(icon, size: 21, color: const Color(0xFF8E8790)),
        suffixIcon: suffixIcon,
        counterText: maxLength == null ? null : '',
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

/// 字段标题行：左侧标题，右侧可选的切换按钮（带图标，如「验证码登录」）。
class _FieldLabelRow extends StatelessWidget {
  const _FieldLabelRow({
    required this.label,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  final String label;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final action = actionLabel;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF292B32),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (action != null && onAction != null)
          TextButton.icon(
            onPressed: onAction,
            icon: Icon(actionIcon ?? Icons.swap_horiz_rounded, size: 15),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF9A3D78),
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            label: Text(action),
          ),
      ],
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