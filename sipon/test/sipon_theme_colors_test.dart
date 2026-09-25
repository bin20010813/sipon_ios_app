import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/app/theme/sipon_theme.dart';
import 'package:sipon/app/theme/sipon_theme_colors.dart';

/// WCAG 2.1 相对对比度。
double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  final lighter = math.max(first, second);
  final darker = math.min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('主题色板完整性', () {
    test('浅色与深色都提供同一套扩展语义色', () {
      final light = SiponThemeColors.light;
      final dark = SiponThemeColors.dark;

      // 同一字段在两种外观下都要有值，且浅深必须不同（浮层、弱底要分层）。
      expect(light.elevatedSurface, isNot(dark.elevatedSurface));
      expect(light.brandSurface, isNot(dark.brandSurface));
      expect(light.glassSurface, isNot(dark.glassSurface));
      expect(light.subtleSurface, isNot(dark.subtleSurface));
      expect(light.skeleton, isNot(dark.skeleton));
      expect(light.success, isNot(dark.success));
      expect(light.successSurface, isNot(dark.successSurface));
      expect(light.warning, isNot(dark.warning));
      expect(light.warningSurface, isNot(dark.warningSurface));
      expect(light.starRating, isNot(dark.starRating));
      expect(light.errorSurface, isNot(dark.errorSurface));
      expect(light.scrim, isNot(dark.scrim));
      expect(light.shadow, isNot(dark.shadow));
      expect(light.pageGradient, hasLength(dark.pageGradient.length));
    });

    test('页面渐变由浅到深覆盖三个色停', () {
      for (final colors in <SiponThemeColors>[
        SiponThemeColors.light,
        SiponThemeColors.dark,
      ]) {
        expect(colors.pageGradient, hasLength(3));
        expect(colors.pageGradient.toSet(), hasLength(3));
      }
    });

    test('copyWith 只替换传入字段', () {
      final updated = SiponThemeColors.dark.copyWith(
        success: const Color(0xFF123456),
      );

      expect(updated.success, const Color(0xFF123456));
      expect(updated.warning, SiponThemeColors.dark.warning);
      expect(updated.brandSurface, SiponThemeColors.dark.brandSurface);
    });

    test('lerp 在两种外观之间插值', () {
      final middle = SiponThemeColors.light.lerp(SiponThemeColors.dark, 0.5);

      expect(
        middle.subtleSurface,
        Color.lerp(
          SiponThemeColors.light.subtleSurface,
          SiponThemeColors.dark.subtleSurface,
          0.5,
        ),
      );
      expect(middle.pageGradient, hasLength(3));
      expect(SiponThemeColors.light.lerp(null, 0.5), SiponThemeColors.light);
    });
  });

  group('主题装配', () {
    test('浅色与深色主题的亮度、底色与扩展一致', () {
      final light = SiponTheme.light;
      final dark = SiponTheme.dark;

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.scaffoldBackgroundColor, const Color(0xFFFBF8F9));
      expect(dark.scaffoldBackgroundColor, const Color(0xFF151216));
      expect(light.extension<SiponThemeColors>(), SiponThemeColors.light);
      expect(dark.extension<SiponThemeColors>(), SiponThemeColors.dark);
      expect(dark.colorScheme.primary, const Color(0xFFE8A0CC));
      expect(light.colorScheme.primary, SiponTheme.brand);
    });

    test('浮层与内嵌底比卡片底色更亮，深色卡片靠层级区分', () {
      // 深色下浮层必须比 surface 更亮，才能在不依赖阴影的情况下分层。
      expect(
        SiponThemeColors.dark.elevatedSurface.computeLuminance(),
        greaterThan(SiponTheme.dark.colorScheme.surface.computeLuminance()),
      );
      expect(
        SiponThemeColors.dark.subtleSurface.computeLuminance(),
        greaterThan(SiponTheme.dark.scaffoldBackgroundColor.computeLuminance()),
      );
    });

    testWidgets('缺少扩展时 siponColors 回退到当前亮度色板', (tester) async {
      late SiponThemeColors resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            colorScheme: SiponTheme.dark.colorScheme,
          ),
          home: Builder(
            builder: (context) {
              resolved = context.siponColors;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(resolved, SiponThemeColors.dark);
    });
  });

  group('可读性对比度', () {
    test('深色正文与次要文字在卡片、页面底、浮层上都不低于 4.5:1', () {
      final scheme = SiponTheme.dark.colorScheme;
      const surfaces = <String, Color>{
        '卡片表面': Color(0xFF211C22),
        '页面底色': Color(0xFF151216),
        '浮层': Color(0xFF2C252D),
      };

      for (final entry in surfaces.entries) {
        expect(
          _contrast(scheme.onSurface, entry.value),
          greaterThanOrEqualTo(4.5),
          reason: '深色 onSurface 在${entry.key}上对比度不足',
        );
        expect(
          _contrast(scheme.onSurfaceVariant, entry.value),
          greaterThanOrEqualTo(4.5),
          reason: '深色 onSurfaceVariant 在${entry.key}上对比度不足',
        );
      }
    });

    test('浅色正文与次要文字在卡片、页面底、浮层上都不低于 4.5:1', () {
      final scheme = SiponTheme.light.colorScheme;
      const surfaces = <String, Color>{
        '卡片表面': Color(0xFFFFFFFF),
        '页面底色': Color(0xFFFBF8F9),
      };

      for (final entry in surfaces.entries) {
        expect(
          _contrast(scheme.onSurface, entry.value),
          greaterThanOrEqualTo(4.5),
          reason: '浅色 onSurface 在${entry.key}上对比度不足',
        );
        expect(
          _contrast(scheme.onSurfaceVariant, entry.value),
          greaterThanOrEqualTo(4.5),
          reason: '浅色 onSurfaceVariant 在${entry.key}上对比度不足',
        );
      }
    });

    test('主按钮文字与底色在所有外观下都满足 4.5:1', () {
      for (final theme in <ThemeData>[SiponTheme.light, SiponTheme.dark]) {
        expect(
          _contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('深色语义色在卡片与浮层上不低于 4.5:1，星标按 3:1', () {
      final scheme = SiponTheme.dark.colorScheme;
      final colors = SiponThemeColors.dark;

      for (final surface in <Color>[
        const Color(0xFF211C22),
        const Color(0xFF2C252D),
      ]) {
        expect(_contrast(scheme.error, surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(colors.success, surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(colors.warning, surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(colors.starRating, surface), greaterThanOrEqualTo(3));
      }
    });

    test('语义色在深色下不得比浅色更弱', () {
      final lightScheme = SiponTheme.light.colorScheme;
      final darkScheme = SiponTheme.dark.colorScheme;
      const lightSurface = Color(0xFFFFFFFF);
      const darkSurface = Color(0xFF211C22);

      expect(
        _contrast(darkScheme.error, darkSurface),
        greaterThanOrEqualTo(_contrast(lightScheme.error, lightSurface)),
      );
      expect(
        _contrast(SiponThemeColors.dark.success, darkSurface),
        greaterThanOrEqualTo(
          _contrast(SiponThemeColors.light.success, lightSurface),
        ),
      );
      expect(
        _contrast(SiponThemeColors.dark.warning, darkSurface),
        greaterThanOrEqualTo(
          _contrast(SiponThemeColors.light.warning, lightSurface),
        ),
      );
    });

    test('品牌弱底、成功弱底与错误弱底上的正文可读', () {
      final dark = SiponThemeColors.dark;
      final onSurface = SiponTheme.dark.colorScheme.onSurface;

      expect(_contrast(onSurface, dark.brandSurface), greaterThanOrEqualTo(4.5));
      expect(
        _contrast(onSurface, dark.successSurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(onSurface, dark.errorSurface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(onSurface, dark.warningSurface),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
