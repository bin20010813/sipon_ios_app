import 'package:flutter/material.dart';

import '../../app/theme/sipon_theme_colors.dart';
import 'language_transform.dart';

class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

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
    final colors = context.siponColors;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: colors.pageGradient,
            stops: const [0, 0.38, 1],
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
                        _LanguageTopBar(
                          title: text.languagePageTitle,
                          back: text.back,
                        ),
                        const SizedBox(height: 20),
                        _LanguageCard(
                          text: text,
                          language: languageController.language,
                          onChanged: (language) {
                            languageController.setLanguage(language);
                            final updatedText = SiponAppText(language);
                            _showMessage(context, updatedText.languageChanged);
                          },
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

class _LanguageTopBar extends StatelessWidget {
  const _LanguageTopBar({required this.title, required this.back});

  final String title;
  final String back;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
                backgroundColor: context.siponColors.glassSurface,
                foregroundColor: scheme.onSurface,
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
              style: TextStyle(
                color: scheme.onSurface,
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

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.text,
    required this.language,
    required this.onChanged,
  });

  final SiponAppText text;
  final SiponLanguage language;
  final ValueChanged<SiponLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.siponColors.glassSurface,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LanguageSectionHeader(
              icon: Icons.translate_rounded,
              title: text.languageTitle,
              trailing: Text(
                text.languageCurrent,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<SiponLanguage>(
                selected: <SiponLanguage>{language},
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return scheme.onPrimary;
                    }
                    return scheme.onSurface;
                  }),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return scheme.primary;
                    }
                    return context.siponColors.elevatedSurface;
                  }),
                  side: WidgetStateProperty.all(
                    BorderSide(color: scheme.outlineVariant),
                  ),
                  textStyle: WidgetStateProperty.all(
                    const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                segments: [
                  ButtonSegment<SiponLanguage>(
                    value: SiponLanguage.zh,
                    icon: const Icon(Icons.language_rounded, size: 16),
                    label: Text(text.languageChinese),
                  ),
                  ButtonSegment<SiponLanguage>(
                    value: SiponLanguage.en,
                    icon: const Icon(Icons.language_rounded, size: 16),
                    label: Text(text.languageEnglish),
                  ),
                ],
                onSelectionChanged: (selection) => onChanged(selection.first),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageSectionHeader extends StatelessWidget {
  const _LanguageSectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: context.siponColors.brandSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: scheme.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
