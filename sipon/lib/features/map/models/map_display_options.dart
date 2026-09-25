/// 可切换的底图样式。MapKit 当前提供 3 个档位：
/// - `standard` 同时承接原来的 light 与 streets；
/// - `muted` 用 muted emphasis + 强制深色界面近似原来的 dark；
/// - `satellite` 用带路名的混合影像，对应原 SATELLITE_STREETS 的观感。
///
/// 这一文件刻意不依赖任何地图引擎包：[MapBaseStyle.id] 是 MethodChannel 的
/// 协议值（见 `SiponMapChannel`），由原生侧翻译成底图配置。
enum MapBaseStyle {
  standard('标准'),
  muted('暗色'),
  satellite('卫星');

  const MapBaseStyle(this.label);

  final String label;

  /// MethodChannel 协议里用的 key，同时也是名字稳定的外部引用。
  String get id => name;

  static MapBaseStyle fromId(String? id) => MapBaseStyle.values.firstWhere(
    (style) => style.id == id,
    orElse: () => MapBaseStyle.standard,
  );
}

/// 圆点完全显现时的不透明度。
const double mapCircleFullOpacity = 0.92;

/// 地图数据的加载态。
///
/// 原来有多个独立加载 bool，但它们永远同时置位，等价于一个状态；合并成这个枚举。
enum MapDataStatus {
  idle('等待地图'),
  loading('正在加载地图数据'),
  ready('地图数据已加载'),
  empty('当前视野暂无可展示酒吧'),
  failed('地图数据加载失败');

  const MapDataStatus(this.label);

  final String label;

  bool get isBusy => this == MapDataStatus.loading;

  /// 只有这两种态需要在顶部提示条上说一句。
  bool get needsBanner =>
      this == MapDataStatus.loading ||
      this == MapDataStatus.empty ||
      this == MapDataStatus.failed;
}
