import 'package:flutter/material.dart';

import 'language_transform.dart';
import 'review_page.dart';

void _openReviewPage(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ReviewPage()));
}

void _showProfileMessage(BuildContext context, String message) {
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

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.bottomOverlayInset = 0});

  final double bottomOverlayInset;

  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);
  static const Color _muted = Color(0xFF8E8790);
  static const Color _line = Color(0xFFF1EBEF);

  static const String _avatarAsset = 'assest/首页/图片素材/Bharat Balami.png';
  static const String _drunkAsset = 'assest/我的/我喝过的@3x.png';
  static const String _wishAsset = 'assest/我的/我想喝的@3x.png';
  static const String _routeAsset = 'assest/我的/酒鬼线路@3x.png';
  static const String _memberAsset = 'assest/我的/Sipon会员@3x.png';
  static const String _couponAsset = 'assest/我的/我的礼券@3x.png';
  static const String _achievementAsset = 'assest/我的/成就勋章@3x.png';
  static const String _feedbackAsset = 'assest/我的/反馈与建议@3x.png';
  static const String _securityAsset = 'assest/我的/安全@3x.png';
  static const String _settingsAsset = 'assest/我的/设置@3x.png';

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
                    padding: EdgeInsets.fromLTRB(
                      24,
                      10,
                      24,
                      26 + bottomOverlayInset,
                    ),
                    sliver: SliverList.list(
                      children: [
                        const _ProfileTopActions(),
                        const SizedBox(height: 22),
                        const _ProfileHeader(),
                        const SizedBox(height: 22),
                        const _QuickEntryCard(),
                        const SizedBox(height: 18),
                        const _BudgetCard(),
                        const SizedBox(height: 22),
                        _SectionTitle(text.benefits),
                        const SizedBox(height: 12),
                        _ProfileListCard(
                          rows: [
                            _ProfileListRow(
                              assetPath: _memberAsset,
                              title: text.membership,
                            ),
                            _ProfileListRow(
                              assetPath: _couponAsset,
                              title: text.vouchers,
                              badge: text.vouchersBadge,
                            ),
                            _ProfileListRow(
                              assetPath: _achievementAsset,
                              title: text.achievements,
                              trailingText: text.achievementsUnlocked,
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        _SectionTitle(text.settingsSupport),
                        const SizedBox(height: 12),
                        _ProfileListCard(
                          rows: [
                            _ProfileListRow(
                              assetPath: _feedbackAsset,
                              title: text.reviewEntry,
                              onTap: () => _openReviewPage(context),
                            ),
                            _ProfileListRow(
                              assetPath: _securityAsset,
                              title: text.accountSecurity,
                            ),
                            _ProfileLanguageRow(
                              assetPath: _settingsAsset,
                              title: text.languageTransformEntry,
                              text: text,
                              language: languageController.language,
                              onChanged: (language) {
                                if (languageController.language == language) {
                                  return;
                                }

                                languageController.setLanguage(language);
                                _showProfileMessage(
                                  context,
                                  SiponAppText(language).languageChanged,
                                );
                              },
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
}

class _ProfileTopActions extends StatelessWidget {
  const _ProfileTopActions();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _TopIconButton(
          tooltip: text.messages,
          icon: Icons.notifications_none_rounded,
          showDot: true,
          onPressed: () {},
        ),
        const SizedBox(width: 10),
        _TopIconButton(
          tooltip: text.settings,
          icon: Icons.settings_outlined,
          onPressed: () => _openReviewPage(context),
        ),
      ],
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.showDot = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            onPressed: onPressed,
            style: IconButton.styleFrom(
              fixedSize: const Size(34, 34),
              padding: EdgeInsets.zero,
              foregroundColor: const Color(0xFF3A3B42),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(icon, size: 25),
          ),
          if (showDot)
            const Positioned(
              right: 7,
              top: 7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ProfilePage._brand,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: 7, height: 7),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const _ProfileAvatar(),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text.profileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleLarge?.copyWith(
                  color: ProfilePage._ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                text.profileId,
                style: textTheme.bodySmall?.copyWith(
                  color: ProfilePage._muted,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () {},
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFB7ABB3),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(64, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text.editProfile, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded, size: 17),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return SizedBox(
      width: 70,
      height: 76,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x269A3D78),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  ProfilePage._avatarAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            bottom: 2,
            child: Container(
              height: 20,
              padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8BD0),
                borderRadius: BorderRadius.circular(11),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33FF80C8),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 8,
                    backgroundColor: Color(0xFFFFD23C),
                    child: Icon(
                      Icons.star_rounded,
                      color: Color(0xFFB12C29),
                      size: 12,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    text.badgeTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
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

class _QuickEntryCard extends StatelessWidget {
  const _QuickEntryCard();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F9A3D78),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: _QuickEntryItem(
                assetPath: ProfilePage._drunkAsset,
                label: text.drank,
              ),
            ),
            const _VerticalDivider(),
            Expanded(
              child: _QuickEntryItem(
                assetPath: ProfilePage._wishAsset,
                label: text.wishList,
              ),
            ),
            const _VerticalDivider(),
            Expanded(
              child: _QuickEntryItem(
                assetPath: ProfilePage._routeAsset,
                label: text.route,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickEntryItem extends StatelessWidget {
  const _QuickEntryItem({required this.assetPath, required this.label});

  final String assetPath;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(assetPath, width: 32, height: 32),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(
                color: ProfilePage._ink,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 42, color: const Color(0xFFF6F1F4));
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x149A3D78),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: ProfilePage._brand,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Icon(
                    Icons.currency_yen_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    text.drinkBudget,
                    style: const TextStyle(
                      color: ProfilePage._ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {},
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(76, 26),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: const Color(0xFFFFEDF7),
                    foregroundColor: ProfilePage._brand,
                  ),
                  icon: const Icon(Icons.add_rounded, size: 15),
                  label: Text(
                    text.addRecord,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(flex: 5, child: _MonthlyExpense()),
                Container(
                  width: 1,
                  height: 74,
                  margin: const EdgeInsets.symmetric(horizontal: 18),
                  color: ProfilePage._line,
                ),
                const Expanded(flex: 4, child: _BudgetStats()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthlyExpense extends StatelessWidget {
  const _MonthlyExpense();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                text.monthlySpend,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: ProfilePage._ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 5),
            const Icon(
              Icons.visibility_off_outlined,
              size: 13,
              color: ProfilePage._muted,
            ),
          ],
        ),
        const SizedBox(height: 9),
        const FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            '¥ 16,542.17',
            style: TextStyle(
              color: ProfilePage._brand,
              fontSize: 25,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: text.monthlyDeltaPrefix),
              const TextSpan(
                text: '↗ 12%',
                style: TextStyle(
                  color: ProfilePage._brand,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          style: const TextStyle(
            color: ProfilePage._muted,
            fontSize: 11,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _BudgetStats extends StatelessWidget {
  const _BudgetStats();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _BudgetStat(label: text.monthlyBudget, value: '¥14,008.00'),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 9),
          child: Divider(height: 1, color: ProfilePage._line),
        ),
        _BudgetStat(label: text.remainingBudget, value: '¥308.00'),
      ],
    );
  }
}

class _BudgetStat extends StatelessWidget {
  const _BudgetStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFC4BBC2),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              color: ProfilePage._brand,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF5D565C),
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    );
  }
}

class _ProfileListCard extends StatelessWidget {
  const _ProfileListCard({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            rows[index],
            if (index != rows.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 42),
                child: Divider(height: 1, color: ProfilePage._line),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProfileLanguageRow extends StatelessWidget {
  const _ProfileLanguageRow({
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
      padding: const EdgeInsets.symmetric(vertical: 13),
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
                color: ProfilePage._ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          _ProfileLanguageToggle(
            text: text,
            language: language,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ProfileLanguageToggle extends StatelessWidget {
  const _ProfileLanguageToggle({
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
        color: const Color(0xFFFFF6FB),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ProfilePage._line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ProfileLanguageOption(
              label: text.languageChinese,
              selected: language == SiponLanguage.zh,
              onTap: () => onChanged(SiponLanguage.zh),
            ),
            _ProfileLanguageOption(
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

class _ProfileLanguageOption extends StatelessWidget {
  const _ProfileLanguageOption({
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
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? ProfilePage._brand : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : ProfilePage._muted,
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

class _ProfileListRow extends StatelessWidget {
  const _ProfileListRow({
    required this.assetPath,
    required this.title,
    this.badge,
    this.trailingText,
    this.onTap,
  });

  final String assetPath;
  final String title;
  final String? badge;
  final String? trailingText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap ?? () {},
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Image.asset(assetPath, width: 26, height: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: ProfilePage._ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEDF7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(
                    color: ProfilePage._brand,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
            if (trailingText != null)
              Text(
                trailingText!,
                style: const TextStyle(
                  color: ProfilePage._brand,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            const SizedBox(width: 7),
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
