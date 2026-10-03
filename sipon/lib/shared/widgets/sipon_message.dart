import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/theme/sipon_theme.dart';
import '../../app/theme/sipon_theme_colors.dart';

enum SiponMessageType { info, success, error }

/// 操作反馈统一入口；需要确认的操作应使用 Dialog，而不是轻提示。
void showSiponMessage(
  BuildContext context,
  String message, {
  SiponMessageType type = SiponMessageType.info,
  Duration? duration,
  ScaffoldMessengerState? messenger,
}) {
  final media = MediaQuery.of(context);
  final target = messenger ?? ScaffoldMessenger.of(context);

  target
    ..clearSnackBars()
    ..removeCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: math.max(
          1,
          math.min(320, media.size.width - media.padding.horizontal - 48),
        ),
        duration:
            duration ??
            (type == SiponMessageType.success
                ? const Duration(milliseconds: 1800)
                : const Duration(seconds: 4)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(),
        padding: EdgeInsets.zero,
        content: _SiponMessageContent(message: message, type: type),
      ),
    );
}

bool _usesCupertino(TargetPlatform platform) =>
    platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

class _SiponMessageContent extends StatelessWidget {
  const _SiponMessageContent({required this.message, required this.type});

  final String message;
  final SiponMessageType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_usesCupertino(theme.platform)) {
      return CupertinoTheme(
        data: CupertinoThemeData(brightness: theme.brightness),
        child: Builder(
          builder: (context) {
            final label = CupertinoColors.label.resolveFrom(context);
            return CupertinoPopupSurface(
              child: _body(
                icon: switch (type) {
                  SiponMessageType.info => CupertinoIcons.info_circle,
                  SiponMessageType.success => CupertinoIcons.check_mark_circled,
                  SiponMessageType.error =>
                    CupertinoIcons.exclamationmark_circle,
                },
                iconColor: type == SiponMessageType.error
                    ? CupertinoColors.systemRed.resolveFrom(context)
                    : label,
                textStyle: CupertinoTheme.of(context).textTheme.textStyle
                    .copyWith(
                      color: label,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            );
          },
        ),
      );
    }

    // 不使用主题动画的中间色，避免亮暗前景/背景交叉渐变时失去对比度。
    final messageTheme = theme.brightness == Brightness.dark
        ? SiponTheme.dark
        : SiponTheme.light;
    final colors = messageTheme.extension<SiponThemeColors>()!;
    final scheme = messageTheme.colorScheme;
    return Material(
      color: colors.elevatedSurface,
      elevation: 3,
      shadowColor: colors.shadow,
      animationDuration: Duration.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: _body(
        icon: switch (type) {
          SiponMessageType.info => Icons.info_outline_rounded,
          SiponMessageType.success => Icons.check_circle_outline_rounded,
          SiponMessageType.error => Icons.error_outline_rounded,
        },
        iconColor: switch (type) {
          SiponMessageType.info => scheme.onSurfaceVariant,
          SiponMessageType.success => colors.success,
          SiponMessageType.error => scheme.error,
        },
        textStyle: messageTheme.textTheme.bodyMedium!.copyWith(
          color: scheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _body({
    required IconData icon,
    required Color iconColor,
    required TextStyle textStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 10),
          Flexible(child: Text(message, style: textStyle)),
        ],
      ),
    );
  }
}
