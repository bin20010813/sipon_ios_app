import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/app/theme/sipon_theme.dart';
import 'package:sipon/app/theme/sipon_theme_colors.dart';
import 'package:sipon/app/theme/sipon_theme_controller.dart';

/// 复刻 `sipon_app.dart` 的主题接线（SiponThemeScope + Builder + MaterialApp），
/// 这样可以在不触发登录、城市与网络流程的前提下单独验证 `themeMode` 行为。
Widget _harness(SiponThemeController controller, {required Widget home}) {
  return SiponThemeScope(
    controller: controller,
    child: Builder(
      builder: (context) {
        final mode = SiponThemeScope.controllerOf(context).mode;
        return MaterialApp(
          theme: SiponTheme.light,
          darkTheme: SiponTheme.dark,
          themeMode: mode,
          home: home,
        );
      },
    ),
  );
}

Brightness _resolvedBrightness(WidgetTester tester, Finder finder) {
  return Theme.of(tester.element(finder)).brightness;
}

void main() {
  testWidgets('跟随系统时，系统亮暗变化立即生效', (tester) async {
    final controller = SiponThemeController();
    addTearDown(controller.dispose);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpWidget(
      _harness(controller, home: const Scaffold(body: Text('home'))),
    );
    expect(
      _resolvedBrightness(tester, find.text('home')),
      Brightness.dark,
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(
      _resolvedBrightness(tester, find.text('home')),
      Brightness.light,
    );
  });

  testWidgets('显式浅色时系统转深色不影响外观', (tester) async {
    final controller = SiponThemeController(initialMode: ThemeMode.light);
    addTearDown(controller.dispose);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpWidget(
      _harness(controller, home: const Scaffold(body: Text('home'))),
    );
    expect(
      _resolvedBrightness(tester, find.text('home')),
      Brightness.light,
    );

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(
      _resolvedBrightness(tester, find.text('home')),
      Brightness.light,
    );
  });

  testWidgets('显式深色时系统浅色不影响外观', (tester) async {
    final controller = SiponThemeController(initialMode: ThemeMode.dark);
    addTearDown(controller.dispose);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpWidget(
      _harness(controller, home: const Scaffold(body: Text('home'))),
    );
    expect(
      _resolvedBrightness(tester, find.text('home')),
      Brightness.dark,
    );
  });

  testWidgets('切换外观时已打开的弹窗保留并立即换色', (tester) async {
    final controller = SiponThemeController(initialMode: ThemeMode.light);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(
        controller,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  backgroundColor: dialogContext.siponColors.elevatedSurface,
                  title: const Text('账本'),
                  content: const Text('弹窗内容'),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('弹窗内容'), findsOneWidget);
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).backgroundColor,
      SiponThemeColors.light.elevatedSurface,
    );

    await controller.setMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    expect(find.text('弹窗内容'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester.widget<AlertDialog>(find.byType(AlertDialog)).backgroundColor,
      SiponThemeColors.dark.elevatedSurface,
    );
  });

  testWidgets('切换外观保留表单内容、路由与滚动位置', (tester) async {
    final controller = SiponThemeController(initialMode: ThemeMode.light);
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      _harness(
        controller,
        home: Scaffold(
          body: Column(
            children: [
              const TextField(decoration: InputDecoration(hintText: '输入')),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: 40,
                  itemBuilder: (context, index) =>
                      SizedBox(height: 60, child: Text('第 $index 行')),
                ),
              ),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const Scaffold(body: Center(child: Text('详情页'))),
                    ),
                  ),
                  child: const Text('打开详情'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '保留这段文字');
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final offsetBeforeSwitch = scrollController.offset;
    expect(offsetBeforeSwitch, greaterThan(0));

    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(find.text('详情页'), findsOneWidget);

    await controller.setMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    // 路由没有重建，被压在下面的首页仍然保留滚动位置与表单内容。
    expect(find.text('详情页'), findsOneWidget);
    expect(find.text('打开详情', skipOffstage: false), findsOneWidget);
    expect(find.text('保留这段文字', skipOffstage: false), findsOneWidget);
    expect(scrollController.offset, offsetBeforeSwitch);
  });
}
