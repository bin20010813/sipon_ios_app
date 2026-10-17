import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/app/theme/sipon_theme.dart';
import 'package:sipon/shared/widgets/sipon_dialog.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness exposes labeled actions and their results', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final open = await _mountDialog(tester, brightness: brightness);

      final confirmed = open();
      await tester.pumpAndSettle();
      final title = tester.getSemantics(find.text('Delete this item?'));
      expect(title.flagsCollection.isHeader, isTrue);
      expect(title.flagsCollection.namesRoute, isTrue);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      semantics.dispose();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(await confirmed, isTrue);
      expect(find.byType(SiponDialog), findsNothing);

      final cancelled = open();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await cancelled, isFalse);
      expect(find.byType(SiponDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$brightness respects barrier dismissal policy', (
      tester,
    ) async {
      final open = await _mountDialog(tester, brightness: brightness);
      final dismissed = open();
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(await dismissed, isNull);
      expect(find.byType(SiponDialog), findsNothing);

      final protectedOpen = await _mountDialog(
        tester,
        brightness: brightness,
        barrierDismissible: false,
      );
      var completed = false;
      final protected = protectedOpen().then((result) {
        completed = true;
        return result;
      });
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(completed, isFalse);
      expect(find.byType(SiponDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await protected, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '$brightness keeps both actions reachable with large text and keyboard',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 568);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        const cancelLabel = 'Cancel and keep this item';
        const confirmLabel = 'Permanently delete this item';
        final open = await _mountDialog(
          tester,
          brightness: brightness,
          textScale: 2,
          keyboardInset: 240,
          title: 'Permanently delete this saved item?',
          cancelLabel: cancelLabel,
          confirmLabel: confirmLabel,
          content: const Text(
            'This item and its saved details will be removed from your '
            'collection. Review your choice before continuing because this '
            'action cannot be undone.',
          ),
        );

        for (final action in {cancelLabel: false, confirmLabel: true}.entries) {
          final result = open();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final actionFinder = find.text(action.key);
          await tester.scrollUntilVisible(
            actionFinder,
            100,
            scrollable: find.descendant(
              of: find.byType(SiponDialog),
              matching: find.byType(Scrollable),
            ),
            maxScrolls: 40,
          );
          await tester.pumpAndSettle();
          expect(actionFinder.hitTestable(), findsOneWidget);
          await tester.tap(actionFinder);
          await tester.pumpAndSettle();
          expect(await result, action.value);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }
}

Future<Future<bool?> Function()> _mountDialog(
  WidgetTester tester, {
  required Brightness brightness,
  bool barrierDismissible = true,
  double textScale = 1,
  double keyboardInset = 0,
  String title = 'Delete this item?',
  String confirmLabel = 'Delete',
  String cancelLabel = 'Cancel',
  Widget content = const Text('This action cannot be undone.'),
}) async {
  late BuildContext pageContext;
  await tester.pumpWidget(
    MaterialApp(
      theme: SiponTheme.light,
      darkTheme: SiponTheme.dark,
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          pageContext = context;
          return const Scaffold(body: Center(child: Text('Collection')));
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return () => showSiponDialog<bool>(
    context: pageContext,
    barrierDismissible: barrierDismissible,
    builder: (context) => SiponDialog(
      title: title,
      content: content,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      destructive: true,
      onCancel: () => Navigator.of(context).pop(false),
      onConfirm: () => Navigator.of(context).pop(true),
    ),
  );
}
