import 'package:flutter/material.dart';

import '../../app/theme/sipon_theme_colors.dart';

/// Shared route treatment for confirmations and short input dialogs.
Future<T?> showSiponDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: context.siponColors.scrim,
    animationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: Duration(milliseconds: 220),
            reverseDuration: Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
  );
}

/// A consistent pair of secondary/primary actions with room for large text.
class SiponDialog extends StatelessWidget {
  const SiponDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
    this.content,
    this.icon = Icons.info_outline_rounded,
    this.destructive = false,
  });

  final String title;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final Widget? content;
  final IconData icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.siponColors;
    final accent = destructive ? scheme.error : scheme.primary;
    final buttonTextStyle = theme.textTheme.labelLarge!.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );

    return Dialog(
      backgroundColor: colors.elevatedSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: colors.shadow,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      insetAnimationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      constraints: const BoxConstraints(maxWidth: 360),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      // Allow the whole card to scroll when a keyboard or larger text leaves
      // little room, so both actions remain reachable on compact screens.
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: ExcludeSemantics(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: destructive
                        ? colors.errorSurface
                        : colors.brandSurface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, size: 27, color: accent),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Semantics(
              namesRoute: true,
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge!.copyWith(
                  color: scheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (content != null) ...[
              const SizedBox(height: 12),
              DefaultTextStyle(
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: 14,
                  height: 1.6,
                  letterSpacing: 0,
                ),
                textAlign: TextAlign.center,
                child: content!,
              ),
            ],
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final secondary = TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurface,
                    backgroundColor: colors.subtleSurface,
                    minimumSize: const Size.fromHeight(50),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    textStyle: buttonTextStyle,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: Text(cancelLabel, textAlign: TextAlign.center),
                );
                final primary = FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    foregroundColor: destructive
                        ? scheme.onError
                        : scheme.onPrimary,
                    backgroundColor: accent,
                    minimumSize: const Size.fromHeight(50),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    textStyle: buttonTextStyle,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(confirmLabel, textAlign: TextAlign.center),
                );

                final availableLabelWidth =
                    (constraints.maxWidth - 12) / 2 - 32;
                final stackActions = [cancelLabel, confirmLabel].any((label) {
                  final painter = TextPainter(
                    text: TextSpan(text: label, style: buttonTextStyle),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout();
                  final tooWide = painter.width > availableLabelWidth;
                  painter.dispose();
                  return tooWide;
                });
                if (stackActions) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [secondary, const SizedBox(height: 10), primary],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: secondary),
                    const SizedBox(width: 12),
                    Expanded(child: primary),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
