import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Visibility;

import 'map_models.dart';

/// 面板的三个吸附档位。
///
/// 面板的连续 extent 有无穷多个中间值，但**需要触发副作用的只有这三个落点**。
/// 把两者分开是这次重构的关键：extent 逐帧变化只用来绘制，stage 变化才去
/// 动相机和地图装饰物（都是异步平台调用，不能逐帧打）。
enum VenueSheetStage {
  /// 悬浮卡片。
  collapsed,

  /// 半屏详情，地图让出下半屏。
  half,

  /// 全屏详情，圆角消失。
  full,
}

/// extent → 档位的判定。收起态与半屏态的分界取两者中点，和
/// [DraggableScrollableSheet] 自己的吸附行为一致。
///
/// 抽成顶层纯函数是为了能被直接测试：档位阈值是这套交互里最容易改错的地方。
VenueSheetStage venueSheetStageForExtent(
  double value, {
  required double collapsedExtent,
}) {
  if (value <= (collapsedExtent + VenueSheetController.halfExtent) / 2) {
    return VenueSheetStage.collapsed;
  }
  if (value <=
      (VenueSheetController.halfExtent + VenueSheetController.maxExtent) / 2) {
    return VenueSheetStage.half;
  }

  return VenueSheetStage.full;
}

/// 酒吧详情面板的状态机。
///
/// 取代原来散在 `_MapPageState` 里的 `_venueSheetExtent` / `_venueSheetSettleTimer`
/// / `_venueSheetAvailableHeight` / `_venueSheetCollapsedExtent` /
/// `_cameraFramedForDetails` 五个字段 —— 其中 `_cameraFramedForDetails` 是个藏在
/// 四个方法里的隐式状态机，现在被 [stage] 显式化了。
class VenueSheetController extends ChangeNotifier {
  static const double halfExtent = 0.55;
  static const double maxExtent = 1.0;

  /// 收起态卡片的固定高度（拖拽手柄 + 内容 + 内边距），用来把像素高度换算成
  /// [DraggableScrollableSheet] 需要的 extent 比例。
  static const double collapsedCardHeight = 154;

  /// 面板、地图相机、悬浮按钮共用同一组时长与曲线，避免多条动画各跑各的节奏。
  static const Duration motionDuration = Duration(milliseconds: 420);
  static const Curve motionCurve = Curves.easeOutCubic;

  /// 手势/动画停下多久算「落定」。相机与装饰物走异步平台通道，不适合逐帧调用。
  static const Duration settleDelay = Duration(milliseconds: 160);

  final DraggableScrollableController sheet = DraggableScrollableController();

  /// 面板当前 extent。**只驱动绘制**：面板形变、悬浮按钮跟随。
  /// 初值 0 表示还没收到过通知，此时按收起态渲染。
  final ValueNotifier<double> extent = ValueNotifier<double>(0);

  ScrollController? _scrollController;
  Timer? _settleTimer;
  double _availableHeight = 0;
  double _collapsedExtent = 0.2;
  VenueSheetStage _stage = VenueSheetStage.collapsed;
  bool _notifyScheduled = false;
  bool _disposed = false;

  double get availableHeight => _availableHeight;
  double get collapsedExtent => _collapsedExtent;
  VenueSheetStage get stage => _stage;
  bool get isCollapsed => _stage == VenueSheetStage.collapsed;

  /// 当前 extent；[extent] 为初值 0 时按收起态处理。
  double get currentExtent {
    final value = extent.value;

    return value <= 0 ? _collapsedExtent : value;
  }

  /// 半屏态相机下边距在 [halfExtent] 基础上的收窄量。
  ///
  /// 聚焦地点会放在「扣除 bottom padding 后的可视区」中心：中心高度 =
  /// (屏高 - padding) / 2。按整份 [halfExtent] 让位时中心落在约 22.5%
  /// 屏高处，叠加 pitch 后视觉上贴顶；收窄一档把中心压回上半屏的视觉重心。
  /// 想再往下移就增大这个值（每加 0.1 中心下移 5% 屏高）。
  static const double cameraPaddingShrink = 0.12;

  /// 相机 padding 的下边距（像素）。收起态不让出空间，展开态让出下半屏。
  double get cameraBottomPadding => _stage == VenueSheetStage.collapsed
      ? 0
      : _availableHeight * (halfExtent - cameraPaddingShrink);

  /// 地图 logo / 版权信息的下边距（像素）。
  ///
  /// 全屏态与半屏态取同一个值：面板此时已经盖住整张地图，把版权推到屏幕外
  /// 没有意义。
  double ornamentBottomMargin(double collapsedMargin) =>
      _stage == VenueSheetStage.collapsed
      ? collapsedMargin
      : _availableHeight * halfExtent + 8;

  /// 收起态 → 半屏的动画进度，驱动卡片形变与内容淡入淡出。
  double progressFor(double value) => mapClamp01(
    (value - _collapsedExtent) /
        math.max(halfExtent - _collapsedExtent, 0.0001),
  );

  /// 半屏 → 全屏的进度，驱动圆角收敛与顶部安全区让位。
  double fullscreenProgressFor(double value) =>
      mapClamp01((value - halfExtent) / (maxExtent - halfExtent));

  /// layout 期调用：**只存值**，不在 build 里 `notifyListeners`。
  ///
  /// 原来直接在 `LayoutBuilder.builder` 里给字段赋值，这里保留「布局算出来的
  /// 数只能从布局来」的事实，但把由它派生的 stage 变化推到帧末再通知。
  void updateMetrics({
    required double availableHeight,
    required double collapsedExtent,
  }) {
    if (_availableHeight == availableHeight &&
        _collapsedExtent == collapsedExtent) {
      return;
    }

    _availableHeight = availableHeight;
    _collapsedExtent = collapsedExtent;
    _moveToStage(_stageForExtent(currentExtent), deferred: true);
  }

  void attachScrollController(ScrollController controller) {
    _scrollController = controller;
  }

  /// 接 `DraggableScrollableNotification`。逐帧只更新 [extent]，
  /// 副作用统一延后到落定。
  bool handleNotification(DraggableScrollableNotification notification) {
    extent.value = notification.extent;
    _settleTimer?.cancel();
    _settleTimer = Timer(settleDelay, _settle);

    return false;
  }

  void _settle() {
    if (_disposed) {
      return;
    }

    final next = _stageForExtent(currentExtent);
    if (next == VenueSheetStage.collapsed) {
      resetScroll();
    }
    _moveToStage(next);
  }

  VenueSheetStage _stageForExtent(double value) =>
      venueSheetStageForExtent(value, collapsedExtent: _collapsedExtent);

  void _moveToStage(VenueSheetStage next, {bool deferred = false}) {
    if (next == _stage) {
      return;
    }

    _stage = next;
    if (!deferred) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) {
      return;
    }

    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  /// 点收起态卡片 → 半屏。
  void expand() {
    if (!sheet.isAttached || currentExtent >= halfExtent - 0.01) {
      return;
    }

    unawaited(
      sheet.animateTo(halfExtent, duration: motionDuration, curve: motionCurve),
    );
  }

  /// 点 × / 点地图空白处 → 收回悬浮卡片。
  void collapse() {
    if (!sheet.isAttached || currentExtent <= _collapsedExtent + 0.001) {
      return;
    }

    unawaited(
      sheet
          .animateTo(
            _collapsedExtent,
            duration: motionDuration,
            curve: motionCurve,
          )
          // 收起后把内部滚动位置归零，否则下次上拖会先滚内容而不是展开面板。
          // 此时详情内容已经完全淡出，归零过程不可见。
          .whenComplete(resetScroll),
    );
  }

  /// 「在地图上查看」：全屏态先退回半屏，好让地图露出来。
  Future<void> settleToHalf() async {
    if (!sheet.isAttached || currentExtent <= halfExtent + 0.01) {
      return;
    }

    await sheet.animateTo(
      halfExtent,
      duration: motionDuration,
      curve: motionCurve,
    );
  }

  void resetScroll() {
    final controller = _scrollController;
    if (_disposed ||
        controller == null ||
        !controller.hasClients ||
        controller.offset == 0) {
      return;
    }

    controller.jumpTo(0);
  }

  @override
  void dispose() {
    _disposed = true;
    _settleTimer?.cancel();
    sheet.dispose();
    extent.dispose();
    super.dispose();
  }
}
