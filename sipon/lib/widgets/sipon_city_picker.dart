import 'package:flutter/material.dart';

import '../pages/language_transform.dart';
import '../services/sipon_city_controller.dart';
import '../services/sipon_data_repository.dart';

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
                    fontWeight: FontWeight.w800,
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
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _SiponCitySheet(),
  );
}

class _SiponCitySheet extends StatefulWidget {
  const _SiponCitySheet();

  @override
  State<_SiponCitySheet> createState() => _SiponCitySheetState();
}

class _SiponCitySheetState extends State<_SiponCitySheet> {
  late final Future<List<String>> _citiesFuture = _loadCities();

  Future<List<String>> _loadCities() async {
    try {
      final cities = await SiponDataRepository.instance.fetchCities();
      if (cities.isNotEmpty) {
        return cities;
      }
    } catch (_) {}

    return const ['上海', '北京', '深圳', '广州', '成都', '杭州'];
  }

  @override
  Widget build(BuildContext context) {
    final cityController = SiponCityScope.controllerOf(context);
    final text = SiponLanguageScope.textOf(context);

    return FutureBuilder<List<String>>(
      future: _citiesFuture,
      builder: (context, snapshot) {
        final cities = snapshot.data ?? const ['上海', '北京', '深圳'];

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final city in cities)
                    _CityChoiceChip(
                      label: text.t(city),
                      selected: city == cityController.city,
                      onTap: () async {
                        await cityController.selectCity(city);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF342C34),
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}
