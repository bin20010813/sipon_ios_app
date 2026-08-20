import 'package:flutter/material.dart';

import 'language_transform.dart';
import 'review_page.dart';

class SettingsSupportPage extends StatelessWidget {
  const SettingsSupportPage({super.key});

  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);
  static const Color _muted = Color(0xFF8E8790);
  static const Color _line = Color(0xFFF1EBEF);

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
                                const _AccountSecurityPage(),
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
  const _AccountSecurityPage();

  @override
  State<_AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<_AccountSecurityPage> {
  bool _biometric = true;
  bool _loginAlert = true;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return _SupportDetailScaffold(
      title: text.accountSecurity,
      children: [
        _SupportHero(
          icon: Icons.verified_user_outlined,
          title: text.t('账号保护中'),
          subtitle: text.t('当前登录环境稳定，建议保持安全提醒开启。'),
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('登录与验证'),
          children: [
            _SupportActionRow(
              icon: Icons.phone_iphone_rounded,
              title: text.t('手机号'),
              subtitle: text.t('186****0921'),
              trailing: text.t('更换'),
            ),
            _SupportActionRow(
              icon: Icons.lock_reset_rounded,
              title: text.t('登录密码'),
              subtitle: text.t('上次更新 32 天前'),
              trailing: text.t('修改'),
            ),
            _SupportSwitchRow(
              icon: Icons.fingerprint_rounded,
              title: text.t('生物识别解锁'),
              subtitle: text.t('用于快速进入 Sipon'),
              value: _biometric,
              onChanged: (value) => setState(() => _biometric = value),
            ),
            _SupportSwitchRow(
              icon: Icons.mark_email_unread_outlined,
              title: text.t('异地登录提醒'),
              subtitle: text.t('发现新设备登录时通知你'),
              value: _loginAlert,
              onChanged: (value) => setState(() => _loginAlert = value),
            ),
          ],
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return _SupportDetailScaffold(
      title: text.aboutUs,
      children: [
        _SupportHero(
          icon: Icons.local_bar_rounded,
          title: text.appTitle,
          subtitle: text.t('记录饮酒偏好，发现附近好酒吧，管理每一次微醺。'),
        ),
        const SizedBox(height: 16),
        _SupportPanel(
          title: text.t('产品信息'),
          children: [
            _SupportInfoRow(label: text.t('版本'), value: '1.0.0'),
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
            ),
            _SupportActionRow(
              icon: Icons.policy_outlined,
              title: text.t('隐私政策'),
              subtitle: text.t('了解数据收集与使用方式'),
              trailing: text.t('查看'),
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
  });

  final IconData icon;
  final String title;
  final String subtitle;

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
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEDF7),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: SettingsSupportPage._brand, size: 26),
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return _SupportBaseRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            trailing,
            style: const TextStyle(
              color: SettingsSupportPage._brand,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xFFC7C1C6),
            size: 20,
          ),
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
            child: Icon(icon, color: SettingsSupportPage._brand, size: 20),
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
