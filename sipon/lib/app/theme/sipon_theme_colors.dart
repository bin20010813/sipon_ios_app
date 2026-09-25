import 'package:flutter/material.dart';

@immutable
class SiponThemeColors extends ThemeExtension<SiponThemeColors> {
  const SiponThemeColors({
    required this.elevatedSurface,
    required this.brandSurface,
    required this.pageGradient,
    required this.glassSurface,
    required this.subtleSurface,
    required this.skeleton,
    required this.success,
    required this.successSurface,
    required this.warning,
    required this.warningSurface,
    required this.starRating,
    required this.errorSurface,
    required this.scrim,
    required this.shadow,
  });

  final Color elevatedSurface;
  final Color brandSurface;
  final List<Color> pageGradient;
  final Color glassSurface;

  /// 内嵌次级容器、输入框底色，比 surface 略深一档。
  final Color subtleSurface;

  /// 加载骨架、图片占位底色。
  final Color skeleton;

  /// 营业中、完成、正向等成功语义色。
  final Color success;

  /// 成功语义的弱底。
  final Color successSurface;

  /// 待处理、提醒等警示语义色。
  final Color warning;

  /// 警示语义的弱底。
  final Color warningSurface;

  /// 评分星标色，属于内容语义色，不随品牌色变化。
  final Color starRating;

  /// 错误语义的弱底。
  final Color errorSurface;

  /// 模态蒙层遮罩色，深色下需要更重才能压住高亮底图。
  final Color scrim;

  /// 卡片阴影色，深色下减少依赖阴影，改用层级与描边。
  final Color shadow;

  static const light = SiponThemeColors(
    elevatedSurface: Color(0xFFFFFFFF),
    brandSurface: Color(0xFFFFEDF7),
    pageGradient: <Color>[
      Color(0xFFFFF2F3),
      Color(0xFFFFFCFC),
      Color(0xFFFFFFFF),
    ],
    glassSurface: Color(0xEBFFFFFF),
    subtleSurface: Color(0xFFFCF8FA),
    skeleton: Color(0xFFF3F0F2),
    success: Color(0xFF3FA66A),
    successSurface: Color(0xFFE8F2E8),
    warning: Color(0xFFE09A35),
    warningSurface: Color(0xFFFFF4E2),
    starRating: Color(0xFFF2A33C),
    errorSurface: Color(0xFFFCE0E4),
    scrim: Color(0x66000000),
    shadow: Color(0x1A000000),
  );

  static const dark = SiponThemeColors(
    elevatedSurface: Color(0xFF2C252D),
    brandSurface: Color(0xFF3B2535),
    pageGradient: <Color>[
      Color(0xFF261B22),
      Color(0xFF1B171C),
      Color(0xFF151216),
    ],
    glassSurface: Color(0xEB211C22),
    subtleSurface: Color(0xFF262027),
    skeleton: Color(0xFF2C252D),
    success: Color(0xFF77D89B),
    successSurface: Color(0xFF22362A),
    warning: Color(0xFFFFC46B),
    warningSurface: Color(0xFF3B2E1C),
    starRating: Color(0xFFFFC46B),
    errorSurface: Color(0xFF3A2224),
    scrim: Color(0x99000000),
    shadow: Color(0x40000000),
  );

  @override
  SiponThemeColors copyWith({
    Color? elevatedSurface,
    Color? brandSurface,
    List<Color>? pageGradient,
    Color? glassSurface,
    Color? subtleSurface,
    Color? skeleton,
    Color? success,
    Color? successSurface,
    Color? warning,
    Color? warningSurface,
    Color? starRating,
    Color? errorSurface,
    Color? scrim,
    Color? shadow,
  }) {
    return SiponThemeColors(
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      brandSurface: brandSurface ?? this.brandSurface,
      pageGradient: pageGradient ?? this.pageGradient,
      glassSurface: glassSurface ?? this.glassSurface,
      subtleSurface: subtleSurface ?? this.subtleSurface,
      skeleton: skeleton ?? this.skeleton,
      success: success ?? this.success,
      successSurface: successSurface ?? this.successSurface,
      warning: warning ?? this.warning,
      warningSurface: warningSurface ?? this.warningSurface,
      starRating: starRating ?? this.starRating,
      errorSurface: errorSurface ?? this.errorSurface,
      scrim: scrim ?? this.scrim,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  SiponThemeColors lerp(covariant SiponThemeColors? other, double t) {
    if (other == null) return this;
    return SiponThemeColors(
      elevatedSurface: Color.lerp(elevatedSurface, other.elevatedSurface, t)!,
      brandSurface: Color.lerp(brandSurface, other.brandSurface, t)!,
      pageGradient: List<Color>.generate(
        pageGradient.length,
        (index) =>
            Color.lerp(pageGradient[index], other.pageGradient[index], t)!,
      ),
      glassSurface: Color.lerp(glassSurface, other.glassSurface, t)!,
      subtleSurface: Color.lerp(subtleSurface, other.subtleSurface, t)!,
      skeleton: Color.lerp(skeleton, other.skeleton, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSurface: Color.lerp(successSurface, other.successSurface, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
      starRating: Color.lerp(starRating, other.starRating, t)!,
      errorSurface: Color.lerp(errorSurface, other.errorSurface, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

extension SiponThemeContext on BuildContext {
  SiponThemeColors get siponColors {
    final theme = Theme.of(this);
    return theme.extension<SiponThemeColors>() ??
        (theme.brightness == Brightness.dark
            ? SiponThemeColors.dark
            : SiponThemeColors.light);
  }
}
