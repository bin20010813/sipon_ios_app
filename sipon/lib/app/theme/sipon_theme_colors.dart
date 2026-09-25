import 'package:flutter/material.dart';

@immutable
class SiponThemeColors extends ThemeExtension<SiponThemeColors> {
  const SiponThemeColors({
    required this.elevatedSurface,
    required this.brandSurface,
    required this.pageGradient,
    required this.glassSurface,
  });

  final Color elevatedSurface;
  final Color brandSurface;
  final List<Color> pageGradient;
  final Color glassSurface;

  static const light = SiponThemeColors(
    elevatedSurface: Color(0xFFFFFFFF),
    brandSurface: Color(0xFFFFEDF7),
    pageGradient: <Color>[
      Color(0xFFFFF2F3),
      Color(0xFFFFFCFC),
      Color(0xFFFFFFFF),
    ],
    glassSurface: Color(0xEBFFFFFF),
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
  );

  @override
  SiponThemeColors copyWith({
    Color? elevatedSurface,
    Color? brandSurface,
    List<Color>? pageGradient,
    Color? glassSurface,
  }) {
    return SiponThemeColors(
      elevatedSurface: elevatedSurface ?? this.elevatedSurface,
      brandSurface: brandSurface ?? this.brandSurface,
      pageGradient: pageGradient ?? this.pageGradient,
      glassSurface: glassSurface ?? this.glassSurface,
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
