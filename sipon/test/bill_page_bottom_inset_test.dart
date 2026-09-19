import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/pages/language_transform.dart';
import 'package:sipon/pages/profile_page.dart';
import 'package:sipon/services/drink_budget_store.dart';
import 'package:sipon/widgets/drink_sticker.dart';

// 账单页(统计)底部安全区回归测试：页面曾在 SafeArea 下被截断，
// 底部小白条区域成为一条不参与滚动的白边，内容无法延伸到屏幕底部。
// 模拟 iPhone 14 Pro（393x852，底部安全区 34）核对修复效果。
void main() {
  testWidgets('账单页滚动视口延伸到屏幕底部，内容可经过小白条区域', (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // mock 掉页面用到的平台插件，避免 MissingPluginException。
    Future<Object?>? prefsHandler(MethodCall call) async {
      return switch (call.method) {
        'getAll' => <String, Object?>{},
        'remove' || 'clear' => true,
        _ => true, // setString/setDouble 等 setValue 类调用
      };
    }

    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences'),
      prefsHandler,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/shared_preferences_android'),
      prefsHandler,
    );
    // StandardMethodCodec.encodeSuccessEnvelope(null)：响应头 0x00 + null 0x00。
    final nullEnvelope = ByteData(2);
    messenger.setMockMessageHandler(
      'sipon/sticker_motion',
      (message) async => nullEnvelope,
    );

    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewPadding = FakeViewPadding(
      left: 0,
      top: 59,
      right: 0,
      bottom: 34,
    );
    // 真机上无键盘时 padding = viewPadding，SafeArea 与页面底部
    // padding 都依赖它。
    tester.view.padding = FakeViewPadding(
      left: 0,
      top: 59,
      right: 0,
      bottom: 34,
    );
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      SiponLanguageScope(
        controller: SiponLanguageController(),
        child: const MaterialApp(home: BudgetBillPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // 塞入示例记录，让明细列表出现。
    final now = DateTime.now();
    for (final (type, place, amount) in const [
      ('鸡尾酒', '庙前冰室', 128.0),
      ('啤酒', '思南精酿', 68.0),
      ('威士忌', 'Speak Low', 238.0),
      ('红酒', '巨鹿路小酒馆', 158.0),
    ]) {
      await DrinkBudgetStore.instance.addRecord(
        DrinkBudgetRecord(
          date: now,
          amount: amount,
          drinkType: type,
          place: place,
          drinkName: type,
          stickerColor: 0xFF9A3D78,
          cups: 1,
          rating: 4,
        ),
      );
    }
    await tester.pump(const Duration(milliseconds: 400));

    // 断言 1：滚动视口必须延伸到屏幕底部（底部 34px 不再被 SafeArea
    // 截成一条静态白边）。屏幕高 852。
    expect(tester.getRect(find.byType(CustomScrollView)).bottom, 852);

    // 滚动到底并落定（贴纸池有持续动画，不能 pumpAndSettle）。
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 80));
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 断言 2：往回滚时明细内容应能经过小白条区域（y > 852 - 34 = 818）。
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    position.jumpTo(position.maxScrollExtent - 60);
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.getRect(find.byType(DrinkSticker).last).bottom,
      greaterThan(818),
    );
  });
}
