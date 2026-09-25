import 'dart:async';

import 'package:flutter/material.dart';

import 'package:sipon/shared/services/sipon_agreement_links.dart';
import 'package:sipon/shared/services/sipon_api_client.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/shared/services/sipon_auth_service.dart';
import 'package:sipon/shared/services/sipon_search_preferences.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/features/reviews/pages/review_page.dart';

class SettingsSupportPage extends StatelessWidget {
  const SettingsSupportPage({super.key, this.onLogoutSucceeded});

  final VoidCallback? onLogoutSucceeded;

  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);
  static const Color _muted = Color(0xFF8E8790);
  static const Color _line = Color(0xFFF1EBEF);
  static const Color _danger = Color(0xFFD64F5A);

  static const String _settingsAsset = 'assest/我的/设置@3x.png';

  void _showMessage(BuildContext context, String message) {
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
    final languageController = SiponLanguageScope.controllerOf(context);
    final text = SiponLanguageScope.textOf(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFF2F3), Color(0xFFFFFCFC), Colors.white],
            stops: [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          // bottom:false 让内容视口延伸到屏幕底，可滚过小白条区域；
          // 底部空间由 CustomScrollView 的 SliverPadding 预留。
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    // 底部预留系统安全区（Home Indicator）。
                    padding: EdgeInsets.fromLTRB(
                      22,
                      10,
                      22,
                      28 + MediaQuery.paddingOf(context).bottom,
                    ),
                    sliver: SliverList.list(
                      children: [
                        _TopBar(title: text.settingsSupport, back: text.back),
                        const SizedBox(height: 20),
                        _SettingsCard(
                          rows: [
                            _LanguageRow(
                              assetPath: _settingsAsset,
                              title: text.languageTransformEntry,
                              text: text,
                              language: languageController.language,
                              onChanged: (language) {
                                if (languageController.language == language) {
                                  return;
                                }

                                languageController.setLanguage(language);
                                _showMessage(
                                  context,
                                  SiponAppText(language).languageChanged,
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SettingsCard(
                          rows: [
                            _SettingsRow(
                              icon: Icons.shield_outlined,
                              title: text.accountSecurity,
                              onTap: () => _openPage(
                                context,
                                _AccountSecurityPage(
                                  onLogoutSucceeded: onLogoutSucceeded,
                                ),
                              ),
                            ),
                            _SettingsRow(
                              icon: Icons.tune_rounded,
                              title: text.preferenceSelection,
                              onTap: () => _openPage(
                                context,
                                const _PreferenceSelectionPage(),
                              ),
                            ),
                            _SettingsRow(
                              icon: Icons.notifications_none_rounded,
                              title: text.notificationSettings,
                              onTap: () => _openPage(
                                context,
                                const _NotificationSettingsPage(),
                              ),
                            ),
                            _SettingsRow(
                              icon: Icons.lock_outline_rounded,
                              title: text.privacySettings,
                              onTap: () => _openPage(
                                context,
                                const _PrivacySettingsPage(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SettingsCard(
                          rows: [
                            _SettingsRow(
                              icon: Icons.thumb_up_alt_outlined,
                              title: text.praiseUs,
                              onTap: () =>
                                  _openPage(context, const _PraiseUsPage()),
                            ),
                            _SettingsRow(
                              icon: Icons.forum_outlined,
                              title: text.featureFeedback,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const ReviewPage(),
                                  ),
                                );
                              },
                            ),
                            _SettingsRow(
                              icon: Icons.info_outline_rounded,
                              title: text.aboutUs,
                              onTap: () =>
                                  _openPage(context, const _AboutUsPage()),
                            ),
                          ],
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

  void _openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _AccountSecurityPage extends StatefulWidget {
  const _AccountSecurityPage({this.onLogoutSucceeded});

  final VoidCallback? onLogoutSucceeded;

  @override
  State<_AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<_AccountSecurityPage> {
  bool _loggingOut = false;
  bool _deleting = false;
  String? _email;
  bool _loadingEmail = true;

  @override
  void initState() {
    super.initState();
    _loadEmail();
  }

  /// 加载当前登录邮箱：优先本地会话，其次拉取个人资料接口。
  Future<void> _loadEmail() async {
    final sessionEmail = SiponAuthService.instance.session?.user['email']
        ?.toString()
        .trim();
    if (sessionEmail != null && sessionEmail.isNotEmpty) {
      if (mounted) {
        setState(() {
          _email = sessionEmail;
          _loadingEmail = false;
        });
      }
      return;
    }
    try {
      final api = SiponApiService();
      dynamic profile;
      try {
        profile = await api.getMyProfile();
      } on Exception {
        profile = await api.getMyOverview();
      }
      final email = profile is Map
          ? (profile['email'] ?? profile['mail'])?.toString().trim()
          : null;
      if (!mounted) return;
      setState(() {
        _email = (email != null && email.isNotEmpty) ? email : null;
        _loadingEmail = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _email = null;
        _loadingEmail = false;
      });
    }
  }

  /// 邮箱脱敏：保留首字符与域名，如 t***@example.com。
  String _maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 1) return email;
    final domain = email.substring(at);
    return '${email[0]}***$domain';
  }

  void _showMessage(BuildContext context, String message) {
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

  /// 弹出确认对话框，用户确认后注销当前账号。
  Future<void> _confirmDeleteAccount() async {
    final text = SiponLanguageScope.textOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(text.t('注销账号')),
          content: Text(text.t('注销后账号数据将被永久删除，且无法恢复。')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(text.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: SettingsSupportPage._danger,
                foregroundColor: Colors.white,
              ),
              child: Text(text.t('删除')),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteAccount();
    }
  }

  /// 调用后端注销账号，成功后清除本地会话并返回首页。
  Future<void> _deleteAccount() async {
    if (_deleting) return;

    setState(() => _deleting = true);
    try {
      await SiponAuthService.instance.deleteAccount();
      if (!mounted) return;

      Navigator.of(context).popUntil((route) => route.isFirst);
      widget.onLogoutSucceeded?.call();
      if (!mounted) return;
      _showMessage(context, SiponLanguageScope.textOf(context).t('账号已注销'));
    } on Exception {
      if (!mounted) return;
      setState(() => _deleting = false);
      _showMessage(
        context,
        SiponLanguageScope.textOf(context).t('账号注销失败，请稍后重试'),
      );
    }
  }

  Future<void> _confirmLogout() async {
    final text = SiponLanguageScope.textOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(text.t('退出登录')),
          content: Text(text.t('退出后需要重新登录才能继续使用 Sipon。')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(text.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: SettingsSupportPage._brand,
                foregroundColor: Colors.white,
              ),
              child: Text(text.t('退出')),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _logout();
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;

    setState(() => _loggingOut = true);
    await SiponAuthService.instance.logout();
    if (!mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onLogoutSucceeded?.call();
  }

  /// 打开修改密码页，预填当前邮箱，走邮箱验证码重置流程。
  void _openChangePassword(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ChangePasswordPage(initialEmail: _email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    final emailSubtitle = _loadingEmail
        ? text.t('加载中')
        : (_email == null || _email!.isEmpty
              ? text.t('未绑定邮箱')
              : _maskEmail(_email!));

    return _SupportDetailScaffold(
      title: text.accountSecurity,
      children: [
        _SupportHero(
          icon: Icons.verified_user_outlined,
          title: text.t('账号保护中'),
          subtitle: text.t('邮箱登录已验证，定期更新密码更安全。'),
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('登录与验证'),
          children: [
            _SupportActionRow(
              icon: Icons.mail_outline_rounded,
              title: text.t('邮箱'),
              subtitle: emailSubtitle,
              trailing: '',
            ),
            _SupportActionRow(
              icon: Icons.lock_reset_rounded,
              title: text.t('登录密码'),
              subtitle: text.t('通过邮箱验证码重置'),
              trailing: text.t('修改'),
              onTap: () => _openChangePassword(context),
            ),
            _SupportActionRow(
              icon: Icons.logout_rounded,
              title: text.t('退出登录'),
              subtitle: text.t('清除本机登录状态'),
              trailing: _loggingOut ? text.t('退出中') : text.t('退出'),
              onTap: _loggingOut ? null : _confirmLogout,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('危险操作'),
          children: [
            _SupportActionRow(
              icon: Icons.person_remove_outlined,
              title: text.t('注销账号'),
              subtitle: text.t('永久删除账号与全部本地数据'),
              trailing: _deleting ? text.t('删除中') : text.t('删除'),
              onTap: _deleting ? null : _confirmDeleteAccount,
              danger: true,
            ),
          ],
        ),
      ],
    );
  }
}

/// 修改密码页：复用登录页同款邮箱验证码重置接口
/// （POST /api/auth/email/password-reset/code + /confirm）。
class _ChangePasswordPage extends StatefulWidget {
  const _ChangePasswordPage({this.initialEmail});

  final String? initialEmail;

  @override
  State<_ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<_ChangePasswordPage> {
  static const _codeCooldownSeconds = 60;

  late final TextEditingController _emailController;
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  Timer? _codeTimer;
  int _codeCountdown = 0;
  bool _sendingCode = false;
  bool _submitting = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  bool _isValidEmail(String email) {
    final at = email.indexOf('@');
    return at > 0 && email.indexOf('.', at) > at + 1;
  }

  bool get _canSubmit {
    if (_submitting) return false;
    if (!_isValidEmail(_emailController.text.trim())) return false;
    if (_codeController.text.trim().length != 6) return false;
    if (_newPasswordController.text.length < 8) return false;
    return _newPasswordController.text == _confirmPasswordController.text;
  }

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _codeTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
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

  /// 发送重置密码验证码，与登录页重置流程共用后端接口。
  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    final text = SiponLanguageScope.textOf(context);
    if (!_isValidEmail(email)) {
      _showMessage(text.t('请填写正确的邮箱地址'));
      return;
    }
    if (_sendingCode || _codeCountdown > 0) return;
    setState(() => _sendingCode = true);
    try {
      await SiponAuthService.instance.requestEmailPasswordResetCode(email);
      if (!mounted) return;
      _showMessage(text.t('验证码已发送，请查收邮箱'));
      setState(() {
        _codeCountdown = _codeCooldownSeconds;
        _codeTimer?.cancel();
        _codeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_codeCountdown <= 1) {
            timer.cancel();
            if (mounted) setState(() => _codeCountdown = 0);
          } else if (mounted) {
            setState(() => _codeCountdown -= 1);
          }
        });
      });
    } on Exception catch (error) {
      _showMessage(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final text = SiponLanguageScope.textOf(context);
    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showMessage(text.t('两次输入的新密码不一致'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      await SiponAuthService.instance.resetEmailPassword(
        email: _emailController.text.trim(),
        code: _codeController.text.trim(),
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      _showMessage(text.t('密码已重置，请重新登录'));
      Navigator.of(context).pop();
    } catch (error) {
      _showMessage(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    return _SupportDetailScaffold(
      title: text.t('修改密码'),
      children: [
        _SupportHero(
          icon: Icons.lock_reset_rounded,
          title: text.t('重置登录密码'),
          subtitle: text.t('验证码将发送到登录邮箱，至少 8 位新密码。'),
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('邮箱验证'),
          children: [
            _ChangePasswordField(
              controller: _emailController,
              hint: text.t('请输入邮箱'),
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
            ),
            Row(
              children: [
                Expanded(
                  child: _ChangePasswordField(
                    controller: _codeController,
                    hint: text.t('请输入验证码'),
                    icon: Icons.shield_outlined,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _sendingCode || _codeCountdown > 0
                        ? null
                        : _sendCode,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SettingsSupportPage._brand,
                      side: const BorderSide(
                        color: SettingsSupportPage._brand,
                      ),
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
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('设置新密码'),
          children: [
            _ChangePasswordField(
              controller: _newPasswordController,
              hint: text.t('请输入密码（至少 8 位）'),
              icon: Icons.lock_outline_rounded,
              obscureText: _obscureNew,
              onChanged: (_) => setState(() {}),
              suffixIcon: IconButton(
                tooltip: text.t(_obscureNew ? '显示密码' : '隐藏密码'),
                onPressed: () =>
                    setState(() => _obscureNew = !_obscureNew),
                icon: Icon(
                  _obscureNew
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
              ),
            ),
            _ChangePasswordField(
              controller: _confirmPasswordController,
              hint: text.t('请再次输入新密码'),
              icon: Icons.lock_outline_rounded,
              obscureText: _obscureConfirm,
              onChanged: (_) => setState(() {}),
              suffixIcon: IconButton(
                tooltip: text.t(_obscureConfirm ? '显示密码' : '隐藏密码'),
                onPressed: () => setState(
                  () => _obscureConfirm = !_obscureConfirm,
                ),
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: SettingsSupportPage._brand,
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
                          text.t('确认修改'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ChangePasswordField extends StatelessWidget {
  const _ChangePasswordField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.suffixIcon,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType keyboardType;
  final int? maxLength;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        obscureText: obscureText,
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
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(
              color: SettingsSupportPage._brand,
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _PreferenceSelectionPage extends StatefulWidget {
  const _PreferenceSelectionPage();

  @override
  State<_PreferenceSelectionPage> createState() =>
      _PreferenceSelectionPageState();
}

class _PreferenceSelectionPageState extends State<_PreferenceSelectionPage> {
  final Set<String> _flavors = {'清爽', '果香'};
  String _scene = '微醺小聚';

  @override
  void initState() {
    super.initState();
    // 兜底：若启动加载尚未完成，进入页面时补一次，保证滑块回显已存值。
    SiponSearchPreferences.instance.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final flavors = ['清爽', '果香', '烟熏', '草本', '甜口', '烈酒感'];
    final scenes = ['微醺小聚', '安静清吧', '餐酒搭配', '派对夜场'];

    return _SupportDetailScaffold(
      title: text.preferenceSelection,
      children: [
        _SupportHero(
          icon: Icons.local_bar_outlined,
          title: text.t('偏好画像'),
          subtitle: text.t('这些选择会用于后续推荐酒款、酒吧和活动。'),
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('搜索半径'),
          children: [
            AnimatedBuilder(
              animation: SiponSearchPreferences.instance,
              builder: (context, _) {
                return _SearchRadiusSlider(
                  radiusMeters: SiponSearchPreferences.instance.radiusMeters,
                  onChanged: SiponSearchPreferences.instance.setRadiusMeters,
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('口味标签'),
          children: [
            _ChoiceWrap(
              values: flavors,
              selectedValues: _flavors,
              onTap: (value) {
                setState(() {
                  if (!_flavors.add(value)) {
                    _flavors.remove(value);
                  }
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('常用场景'),
          children: [
            _ChoiceWrap(
              values: scenes,
              selectedValues: {_scene},
              onTap: (value) => setState(() => _scene = value),
            ),
          ],
        ),
      ],
    );
  }
}

/// 搜索半径卡片：说明行 + 居中大数值 + 宽滑块 + 两端刻度，
/// 档位由 [SiponSearchPreferences.radiusStepMeters] 决定（1~3km 共 5 档）。
class _SearchRadiusSlider extends StatelessWidget {
  const _SearchRadiusSlider({
    required this.radiusMeters,
    required this.onChanged,
  });

  final int radiusMeters;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final label = siponFormatRadiusMeters(radiusMeters);
    const minRadius = SiponSearchPreferences.minRadiusMeters;
    const maxRadius = SiponSearchPreferences.maxRadiusMeters;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF6FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: SettingsSupportPage._brand,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text.t('打卡与路线规划按此范围查找附近酒吧'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SettingsSupportPage._muted,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: Text(
                label,
                key: ValueKey<String>(label),
                style: const TextStyle(
                  color: SettingsSupportPage._brand,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              text.t('拖动滑块调整搜索范围'),
              style: const TextStyle(
                color: SettingsSupportPage._muted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: SettingsSupportPage._brand,
              inactiveTrackColor: const Color(0xFFF3E4EF),
              thumbColor: SettingsSupportPage._brand,
              overlayColor: SettingsSupportPage._brand.withValues(alpha: 0.10),
              trackHeight: 5,
            ),
            child: Slider(
              value: radiusMeters.toDouble(),
              min: minRadius.toDouble(),
              max: maxRadius.toDouble(),
              divisions:
                  (maxRadius - minRadius) ~/
                  SiponSearchPreferences.radiusStepMeters,
              onChanged: (value) => onChanged(value.round()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  siponFormatRadiusMeters(minRadius),
                  style: const TextStyle(
                    color: SettingsSupportPage._muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  siponFormatRadiusMeters(maxRadius),
                  style: const TextStyle(
                    color: SettingsSupportPage._muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
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

class _NotificationSettingsPage extends StatefulWidget {
  const _NotificationSettingsPage();

  @override
  State<_NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<_NotificationSettingsPage> {
  bool _activity = true;
  bool _budget = true;
  bool _recommend = false;
  bool _system = true;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return _SupportDetailScaffold(
      title: text.notificationSettings,
      children: [
        _SupportHero(
          icon: Icons.notifications_active_outlined,
          title: text.t('消息偏好'),
          subtitle: text.t('先保存在本地状态，接口接入后同步到账号。'),
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('通知类型'),
          children: [
            _SupportSwitchRow(
              icon: Icons.event_available_outlined,
              title: text.t('活动与预约'),
              subtitle: text.t('酒吧活动、预约状态和到店提醒'),
              value: _activity,
              onChanged: (value) => setState(() => _activity = value),
            ),
            _SupportSwitchRow(
              icon: Icons.account_balance_wallet_outlined,
              title: text.t('预算提醒'),
              subtitle: text.t('月预算接近上限时提醒'),
              value: _budget,
              onChanged: (value) => setState(() => _budget = value),
            ),
            _SupportSwitchRow(
              icon: Icons.auto_awesome_outlined,
              title: text.t('个性推荐'),
              subtitle: text.t('推荐酒款、酒吧和榜单内容'),
              value: _recommend,
              onChanged: (value) => setState(() => _recommend = value),
            ),
            _SupportSwitchRow(
              icon: Icons.security_update_good_outlined,
              title: text.t('系统通知'),
              subtitle: text.t('账号、安全和服务变更通知'),
              value: _system,
              onChanged: (value) => setState(() => _system = value),
            ),
          ],
        ),
      ],
    );
  }
}

class _PrivacySettingsPage extends StatefulWidget {
  const _PrivacySettingsPage();

  @override
  State<_PrivacySettingsPage> createState() => _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends State<_PrivacySettingsPage> {
  bool _profileVisible = true;
  bool _recordVisible = false;
  bool _locationEnabled = true;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return _SupportDetailScaffold(
      title: text.privacySettings,
      children: [
        _SupportHero(
          icon: Icons.privacy_tip_outlined,
          title: text.t('隐私控制'),
          subtitle: text.t('管理资料展示、饮酒记录和位置权限的可见范围。'),
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('可见范围'),
          children: [
            _SupportSwitchRow(
              icon: Icons.person_search_outlined,
              title: text.t('公开个人主页'),
              subtitle: text.t('允许其他用户看到昵称、头像和勋章'),
              value: _profileVisible,
              onChanged: (value) => setState(() => _profileVisible = value),
            ),
            _SupportSwitchRow(
              icon: Icons.receipt_long_outlined,
              title: text.t('展示饮酒记录'),
              subtitle: text.t('仅展示酒款与地点，不展示金额'),
              value: _recordVisible,
              onChanged: (value) => setState(() => _recordVisible = value),
            ),
            _SupportSwitchRow(
              icon: Icons.location_on_outlined,
              title: text.t('使用位置推荐'),
              subtitle: text.t('用于附近酒吧、距离和城市榜单'),
              value: _locationEnabled,
              onChanged: (value) => setState(() => _locationEnabled = value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('数据管理'),
          children: [
            _SupportActionRow(
              icon: Icons.file_download_outlined,
              title: text.t('导出个人数据'),
              subtitle: text.t('饮酒记录、预算和偏好设置'),
              trailing: text.t('申请'),
            ),
            _SupportActionRow(
              icon: Icons.delete_outline_rounded,
              title: text.t('清除本地缓存'),
              subtitle: text.t('不影响账号云端数据'),
              trailing: text.t('清理'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PraiseUsPage extends StatelessWidget {
  const _PraiseUsPage();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return _SupportDetailScaffold(
      title: text.praiseUs,
      children: [
        _SupportHero(
          icon: Icons.favorite_border_rounded,
          title: text.t('感谢你的喜欢'),
          subtitle: text.t('等应用商店链接接入后，这里会跳转到评分页。'),
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('可以这样支持我们'),
          children: [
            _SupportActionRow(
              icon: Icons.star_rate_rounded,
              title: text.t('去应用商店评分'),
              subtitle: text.t('给 Sipon 一个真实评分'),
              trailing: text.t('待接入'),
            ),
            _SupportActionRow(
              icon: Icons.ios_share_rounded,
              title: text.t('分享给朋友'),
              subtitle: text.t('邀请朋友一起记录微醺地图'),
              trailing: text.t('待接入'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AboutUsPage extends StatelessWidget {
  const _AboutUsPage();

  /// 在系统浏览器中打开指定协议官网地址，失败时给出提示。
  Future<void> _openAgreement(BuildContext context, String url) async {
    final opened = await openAgreementInBrowser(url);
    if (!opened && context.mounted) {
      final text = SiponLanguageScope.textOf(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(text.t('无法打开链接，请稍后重试。')),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return _SupportDetailScaffold(
      title: text.aboutUs,
      children: [
        _SupportHero(
          icon: Icons.local_bar_rounded,
          assetPath: 'assest/logo.png',
          title: text.appTitle,
          subtitle: text.t('Turn the SIP ON，开饮 就现在'),
          centered: true,
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('产品信息'),
          children: [
            _SupportInfoRow(label: text.t('版本'), value: '1.0.0'),
            _SupportInfoRow(label: text.t('服务名称(APP)'), value: 'SipOn酒吧地图'),
            _SupportInfoRow(label: text.t('服务备案号'), value: '浙ICP备2026046724号-2A'),
            _SupportInfoRow(label: text.t('服务邮箱'), value: 'support@sipon.app'),
            _SupportInfoRow(label: text.t('官方网站'), value: 'sipon.app'),
          ],
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('协议与说明'),
          children: [
            _SupportActionRow(
              icon: Icons.description_outlined,
              title: text.t('用户协议'),
              subtitle: text.t('查看 Sipon 服务条款'),
              trailing: text.t('查看'),
              onTap: () => _openAgreement(
                context,
                kSiponUserAgreementUrl,
              ),
            ),
            _SupportActionRow(
              icon: Icons.policy_outlined,
              title: text.t('隐私政策'),
              subtitle: text.t('了解数据收集与使用方式'),
              trailing: text.t('查看'),
              onTap: () => _openAgreement(
                context,
                kSiponPrivacyPolicyUrl,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SupportDetailScaffold extends StatelessWidget {
  const _SupportDetailScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFF2F3), Color(0xFFFFFCFC), Colors.white],
            stops: [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          // bottom:false 让内容视口延伸到屏幕底，可滚过小白条区域；
          // 底部空间由 CustomScrollView 的 SliverPadding 预留。
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    // 底部预留系统安全区（Home Indicator）。
                    padding: EdgeInsets.fromLTRB(
                      22,
                      10,
                      22,
                      28 + MediaQuery.paddingOf(context).bottom,
                    ),
                    sliver: SliverList.list(
                      children: [
                        _TopBar(title: title, back: text.back),
                        const SizedBox(height: 20),
                        ...children,
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

class _SupportHero extends StatelessWidget {
  const _SupportHero({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.centered = false,
    this.assetPath,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool centered;
  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
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
        padding: EdgeInsets.all(centered ? 24 : 18),
        child: centered
            ? Column(
                children: [
                  _SupportHeroMark(
                    icon: icon,
                    assetPath: assetPath,
                    size: 76,
                    borderRadius: 22,
                    iconSize: 42,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: SettingsSupportPage._ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: SettingsSupportPage._muted,
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  _SupportHeroMark(
                    icon: icon,
                    assetPath: assetPath,
                    size: 48,
                    borderRadius: 14,
                    iconSize: 26,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SettingsSupportPage._ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: SettingsSupportPage._muted,
                            fontSize: 12,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
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

class _SupportHeroMark extends StatelessWidget {
  const _SupportHeroMark({
    required this.icon,
    required this.size,
    required this.borderRadius,
    required this.iconSize,
    this.assetPath,
  });

  final IconData icon;
  final double size;
  final double borderRadius;
  final double iconSize;
  final String? assetPath;

  @override
  Widget build(BuildContext context) {
    final path = assetPath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: path == null
            ? ColoredBox(
                color: const Color(0xFFFFEDF7),
                child: Icon(
                  icon,
                  color: SettingsSupportPage._brand,
                  size: iconSize,
                ),
              )
            : Image.asset(path, fit: BoxFit.cover),
      ),
    );
  }
}

class _SupportPanel extends StatelessWidget {
  const _SupportPanel({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: SettingsSupportPage._ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SupportActionRow extends StatelessWidget {
  const _SupportActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;

  /// 危险操作样式：图标与文案使用警示色。
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final highlightColor = danger
        ? SettingsSupportPage._danger
        : SettingsSupportPage._brand;

    return _SupportBaseRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      highlightColor: highlightColor,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            trailing,
            style: TextStyle(
              color: highlightColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          // 不可点击的行（如纯展示的邮箱）不显示箭头，避免误导。
          if (onTap != null) ...[
            const SizedBox(width: 2),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFC7C1C6),
              size: 20,
            ),
          ],
        ],
      ),
    );
  }
}

class _SupportSwitchRow extends StatelessWidget {
  const _SupportSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SupportBaseRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: SettingsSupportPage._brand,
        activeTrackColor: const Color(0xFFFFD8EC),
      ),
    );
  }
}

class _SupportBaseRow extends StatelessWidget {
  const _SupportBaseRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    this.highlightColor = SettingsSupportPage._brand,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  /// 图标高亮色，默认使用品牌色；危险操作传入警示色。
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6FB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: highlightColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SettingsSupportPage._ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SettingsSupportPage._muted,
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _SupportInfoRow extends StatelessWidget {
  const _SupportInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: SettingsSupportPage._muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: SettingsSupportPage._ink,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChoiceWrap extends StatelessWidget {
  const _ChoiceWrap({
    required this.values,
    required this.selectedValues,
    required this.onTap,
  });

  final List<String> values;
  final Set<String> selectedValues;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final value in values)
            ChoiceChip(
              label: Text(text.t(value)),
              selected: selectedValues.contains(value),
              onSelected: (_) => onTap(value),
              selectedColor: const Color(0xFFFFEDF7),
              backgroundColor: const Color(0xFFFCF8FA),
              side: BorderSide(
                color: selectedValues.contains(value)
                    ? SettingsSupportPage._brand
                    : SettingsSupportPage._line,
              ),
              labelStyle: TextStyle(
                color: selectedValues.contains(value)
                    ? SettingsSupportPage._brand
                    : SettingsSupportPage._muted,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.back});

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
                foregroundColor: SettingsSupportPage._ink,
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
                color: SettingsSupportPage._ink,
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

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: SettingsSupportPage._line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F9A3D78),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            for (var index = 0; index < rows.length; index++) ...[
              rows[index],
              if (index != rows.length - 1)
                const Padding(
                  padding: EdgeInsets.only(left: 42),
                  child: Divider(height: 1, color: SettingsSupportPage._line),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.icon, required this.title, this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        child: Row(
          children: [
            Icon(icon, color: SettingsSupportPage._brand, size: 25),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: SettingsSupportPage._ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFC7C1C6),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.assetPath,
    required this.title,
    required this.text,
    required this.language,
    required this.onChanged,
  });

  final String assetPath;
  final String title;
  final SiponAppText text;
  final SiponLanguage language;
  final ValueChanged<SiponLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
      child: Row(
        children: [
          Image.asset(assetPath, width: 26, height: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SettingsSupportPage._ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6FB),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: SettingsSupportPage._line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LanguageOption(
                    label: text.languageChinese,
                    selected: language == SiponLanguage.zh,
                    onTap: () => onChanged(SiponLanguage.zh),
                  ),
                  _LanguageOption(
                    label: text.languageEnglish,
                    selected: language == SiponLanguage.en,
                    onTap: () => onChanged(SiponLanguage.en),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
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
          borderRadius: BorderRadius.circular(13),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? SettingsSupportPage._brand : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : SettingsSupportPage._muted,
                fontSize: 11,
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
