import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:sipon/shared/localization/language_transform.dart';
import '../services/sipon_city_controller.dart';
import '../services/sipon_region_data.dart';
import '../services/sipon_region_repository.dart';

class SiponCityScope extends InheritedNotifier<SiponCityController> {
  const SiponCityScope({
    super.key,
    required SiponCityController controller,
    required super.child,
  }) : super(notifier: controller);

  static SiponCityController controllerOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SiponCityScope>();
    assert(scope?.notifier != null, 'SiponCityScope was not found.');
    return scope!.notifier!;
  }
}

class SiponCityButton extends StatelessWidget {
  const SiponCityButton({
    super.key,
    this.compact = false,
    this.backgroundColor = Colors.white,
    this.foregroundColor = const Color(0xFF252229),
  });

  final bool compact;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final controller = SiponCityScope.controllerOf(context);
    final text = SiponLanguageScope.textOf(context);

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(compact ? 15 : 17),
      child: InkWell(
        onTap: () => showSiponCitySheet(context),
        borderRadius: BorderRadius.circular(compact ? 15 : 17),
        child: Container(
          height: compact ? 34 : 44,
          constraints: BoxConstraints(
            minWidth: compact ? 78 : 92,
            maxWidth: compact ? 118 : 138,
          ),
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 15 : 17),
            border: Border.all(color: const Color(0x229A3D78)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on_outlined,
                color: const Color(0xFF9A3D78),
                size: compact ? 16 : 18,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  text.t(controller.city),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 1),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: foregroundColor.withValues(alpha: 0.68),
                size: compact ? 17 : 19,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showSiponCitySheet(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const SiponCityPickerPage()),
  );
}

class SiponCityPickerPage extends StatelessWidget {
  const SiponCityPickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF252229),
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const _SiponCitySheet(),
    );
  }
}

class _SiponCitySheet extends StatefulWidget {
  const _SiponCitySheet();

  @override
  State<_SiponCitySheet> createState() => _SiponCitySheetState();
}

class _SiponCitySheetState extends State<_SiponCitySheet> {
  late final Future<List<SiponProvinceGroup>> _groupsFuture =
      SiponRegionRepository.instance.loadGroups();

  /// 定位状态：进入选择器自动获取当前位置，失败则提示手动选择。
  SiponLocateResult? _locateResult;
  bool _locating = true;
  bool _didStartLocate = false;

  /// 左侧选中的省级分组下标；null 表示还没按当前城市定位。
  int? _selectedProvinceIndex;

  /// 按当前城市定位左侧分组：优先完全匹配省份，其次按城市反查。
  int _locateProvinceIndex(
    List<SiponProvinceGroup> groups,
    SiponCityController cityController,
  ) {
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].province == cityController.province) {
        return i;
      }
    }
    final provinceOfCity = siponFindProvinceOfCity(cityController.city);
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].province == provinceOfCity) {
        return i;
      }
      if (groups[i].cities.any((city) => city.city == cityController.city)) {
        return i;
      }
    }
    return 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didStartLocate) {
      _didStartLocate = true;
      _startLocate();
    }
  }

  Future<void> _startLocate() async {
    final controller = SiponCityScope.controllerOf(context);
    final result = await controller.locateCurrentCity();
    if (!mounted) return;
    setState(() {
      _locateResult = result;
      _locating = false;
    });
  }

  Future<void> _retryLocate() async {
    setState(() {
      _locating = true;
      _locateResult = null;
    });
    await _startLocate();
  }

  @override
  Widget build(BuildContext context) {
    final cityController = SiponCityScope.controllerOf(context);
    final text = SiponLanguageScope.textOf(context);

    return FutureBuilder<List<SiponProvinceGroup>>(
      future: _groupsFuture,
      builder: (context, snapshot) {
        final groups = snapshot.data;
        if (groups == null || groups.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: Color(0xFF9A3D78)),
            ),
          );
        }

        final isZh = SiponLanguageScope.languageOf(context) == SiponLanguage.zh;
        final provinceIndex =
            _selectedProvinceIndex ??
            _locateProvinceIndex(groups, cityController);
        final clampedIndex = provinceIndex.clamp(0, groups.length - 1);
        final activeGroup = groups[clampedIndex];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text.t('选择城市'),
                          style: const TextStyle(
                            color: Color(0xFF252229),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          text.t('城市变化后会刷新附近酒吧和地图内容'),
                          style: const TextStyle(
                            color: Color(0xFF8F8790),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CurrentCityTag(city: cityController.city),
                ],
              ),
            ),
            _LocateBanner(
              locating: _locating,
              result: _locateResult,
              currentCity: cityController.city,
              isZh: isZh,
              onSwitch: (cityEntry) async {
                await cityController.selectCity(
                  cityEntry.name,
                  province: siponFindProvinceOfCity(cityEntry.name),
                );
                if (mounted) setState(() {});
              },
              onRetry: _retryLocate,
              onOpenAppSettings: () => Geolocator.openAppSettings(),
              onOpenLocationSettings: () => Geolocator.openLocationSettings(),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左侧：省级列表。
                  Container(
                    width: 112,
                    color: const Color(0xFFF8F4F7),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        final selected = index == clampedIndex;
                        return _ProvinceTile(
                          label: groups[index].displayName(isZh),
                          selected: selected,
                          onTap: () => setState(
                            () => _selectedProvinceIndex = index,
                          ),
                        );
                      },
                    ),
                  ),
                  // 右侧：该省下辖市。
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 10, 20, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            mainAxisExtent: 38,
                          ),
                      itemCount: activeGroup.cities.length,
                      itemBuilder: (context, index) {
                        final option = activeGroup.cities[index];
                        return _CityChoiceChip(
                          label: option.displayName(isZh),
                          selected: option.city == cityController.city,
                          onTap: () async {
                            await cityController.selectCity(
                              option.city,
                              province: option.province.isEmpty
                                  ? null
                                  : option.province,
                            );
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProvinceTile extends StatelessWidget {
  const _ProvinceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected
                    ? const Color(0xFF9A3D78)
                    : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF9A3D78)
                  : const Color(0xFF342C34),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentCityTag extends StatelessWidget {
  const _CurrentCityTag({required this.city});

  final String city;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x229A3D78)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_on_outlined,
            color: Color(0xFF9A3D78),
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            SiponLanguageScope.textOf(context).t('当前：$city'),
            style: const TextStyle(
              color: Color(0xFF9A3D78),
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocateBanner extends StatelessWidget {
  const _LocateBanner({
    required this.locating,
    required this.result,
    required this.currentCity,
    required this.isZh,
    required this.onSwitch,
    required this.onRetry,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final bool locating;
  final SiponLocateResult? result;
  final String currentCity;
  final bool isZh;
  final ValueChanged<SiponCityEntry> onSwitch;
  final VoidCallback onRetry;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    Widget banner({
      required IconData icon,
      required String message,
      List<Widget> actions = const [],
    }) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F4F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x159A3D78)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF9A3D78), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF342C34),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 10),
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                actions[i],
              ],
            ],
          ],
        ),
      );
    }

    if (locating) {
      return banner(
        icon: Icons.my_location_rounded,
        message: text.t('正在定位…'),
        actions: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF9A3D78),
            ),
          ),
        ],
      );
    }

    final locate = result;
    if (locate == null) {
      return banner(
        icon: Icons.location_off_rounded,
        message: text.t('定位失败，请手动选择城市'),
        actions: [
          _BannerAction(label: text.t('重试'), onTap: onRetry),
        ],
      );
    }

    switch (locate.status) {
      case SiponLocateStatus.success:
        final city = locate.city!;
        final display = isZh ? city.name : city.nameEn;
        if (city.name == currentCity) {
          return banner(
            icon: Icons.check_circle_rounded,
            message: '${text.t('已定位到当前城市')} · $display',
          );
        }
        return banner(
          icon: Icons.near_me_rounded,
          message: '${text.t('检测到您在')}$display${text.t('，是否切换？')}',
          actions: [
            _BannerAction(label: text.t('切换'), onTap: () => onSwitch(city)),
          ],
        );
      case SiponLocateStatus.serviceDisabled:
        return banner(
          icon: Icons.location_off_rounded,
          message: text.t('定位服务未开启，请手动选择城市'),
          actions: [
            _BannerAction(
                label: text.t('去设置'), onTap: onOpenLocationSettings),
            _BannerAction(label: text.t('重试'), onTap: onRetry),
          ],
        );
      case SiponLocateStatus.permissionDenied:
      case SiponLocateStatus.permissionDeniedForever:
      case SiponLocateStatus.failed:
        return banner(
          icon: Icons.location_off_rounded,
          message: text.t('未获得定位权限，请手动选择城市'),
          actions: [
            _BannerAction(label: text.t('去设置'), onTap: onOpenAppSettings),
            _BannerAction(label: text.t('重试'), onTap: onRetry),
          ],
        );
    }
  }
}

class _BannerAction extends StatelessWidget {
  const _BannerAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF9A3D78),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _CityChoiceChip extends StatelessWidget {
  const _CityChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF9A3D78) : const Color(0xFFFFF7FC),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected
                  ? const Color(0xFF9A3D78)
                  : const Color(0x229A3D78),
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF342C34),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}
