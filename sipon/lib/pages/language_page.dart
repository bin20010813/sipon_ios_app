import 'package:flutter/material.dart';

import 'language_transform.dart';

class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);
  static const Color _muted = Color(0xFF8E8790);
  static const Color _line = Color(0xFFF1EBEF);

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
                foregroundColor: LanguagePage._ink,
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
                color: LanguagePage._ink,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LanguageSectionHeader(
              icon: Icons.translate_rounded,
              title: text.languageTitle,
              trailing: Text(
                text.languageCurrent,
                style: const TextStyle(
                  color: LanguagePage._muted,
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
                      return Colors.white;
                    }
                    return LanguagePage._ink;
                  }),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return LanguagePage._brand;
                    }
                    return Colors.white;
                  }),
                  side: WidgetStateProperty.all(
                    const BorderSide(color: LanguagePage._line),
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
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEDF7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: LanguagePage._brand, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: LanguagePage._ink,
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
