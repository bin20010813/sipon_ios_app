import 'package:flutter/material.dart';
import '../../../../app/theme/sipon_theme_colors.dart';

import '../data/drink_budget_store.dart';
import '../widgets/drink_sticker.dart';
import '../../../../shared/localization/language_transform.dart';

class DrinkStickerCalendarPage extends StatefulWidget {
  const DrinkStickerCalendarPage({super.key, this.onRecordPressed});

  final VoidCallback? onRecordPressed;

  @override
  State<DrinkStickerCalendarPage> createState() =>
      _DrinkStickerCalendarPageState();
}

class _DrinkStickerCalendarPageState extends State<DrinkStickerCalendarPage> {

  final DrinkBudgetStore _store = DrinkBudgetStore.instance;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _store.addListener(_onStoreChanged);
    _store.ensureLoaded().then((_) => _store.ensureSynced());
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Map<int, List<DrinkBudgetRecord>> _recordsByDay() {
    final grouped = <int, List<DrinkBudgetRecord>>{};
    for (final record in _store.recordsOf(
      DrinkBudgetMonth(_month.year, _month.month),
    )) {
      grouped.putIfAbsent(record.date.day, () => []).add(record);
    }
    return grouped;
  }

  String _monthTitle(SiponAppText text) {
    if (text.isZh) return '${_month.year}年${_month.month}月';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[_month.month - 1]} ${_month.year}';
  }

  void _showDayRecords(int day, List<DrinkBudgetRecord> records) {
    final text = SiponLanguageScope.textOf(context);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                text.isZh ? '${_month.month}月$day日' : '${_month.month}/$day',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 14),
              for (final record in records)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      DrinkSticker(record: record, size: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              drinkStickerTitle(record),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${text.t(record.place)} · ¥${record.amount.toStringAsFixed(0)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final grouped = _recordsByDay();
    final monthRecords = grouped.values.expand((records) => records).toList();
    final total = monthRecords.fold<double>(
      0,
      (sum, record) => sum + record.amount,
    );
    final activeDays = grouped.values
        .where((records) => records.isNotEmpty)
        .length;
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);
    final firstWeekday = DateTime(_month.year, _month.month).weekday;
    final cells = firstWeekday - 1 + daysInMonth;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        // bottom:false 让内容视口延伸到屏幕底，可滚过小白条区域；
        // 底部空间由 CustomScrollView 的 SliverPadding 预留。
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  // 底部预留系统安全区（Home Indicator）。
                  padding: EdgeInsets.fromLTRB(
                    20,
                    8,
                    20,
                    26 + MediaQuery.paddingOf(context).bottom,
                  ),
                  sliver: SliverList.list(
                    children: [
                      SizedBox(
                        height: 48,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            tooltip: text.back,
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => setState(
                              () => _month = DateTime(
                                _month.year,
                                _month.month - 1,
                              ),
                            ),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: Text(
                              _monthTitle(text),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(
                              () => _month = DateTime(
                                _month.year,
                                _month.month + 1,
                              ),
                            ),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _MonthSummary(
                        records: monthRecords.length,
                        days: activeDays,
                        total: total,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          for (final label in const [
                            '一',
                            '二',
                            '三',
                            '四',
                            '五',
                            '六',
                            '日',
                          ])
                            Expanded(
                              child: Center(
                                child: Text(
                                  text.t(label),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cells,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              mainAxisSpacing: 7,
                              crossAxisSpacing: 7,
                              childAspectRatio: 0.72,
                            ),
                        itemBuilder: (context, index) {
                          final day = index - firstWeekday + 2;
                          if (day < 1 || day > daysInMonth) {
                            return const SizedBox.shrink();
                          }
                          final records =
                              grouped[day] ?? const <DrinkBudgetRecord>[];
                          return _CalendarDayCell(
                            records: records,
                            onTap: records.isEmpty
                                ? null
                                : () => _showDayRecords(day, records),
                          );
                        },
                      ),
                      if (widget.onRecordPressed != null) ...[
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: widget.onRecordPressed,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Theme.of(context).colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 21),
                          label: Text(
                            text.addRecord,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({
    required this.records,
    required this.days,
    required this.total,
  });

  final int records;
  final int days;
  final double total;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: context.siponColors.brandSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          _SummaryMetric(label: text.t('贴纸'), value: '$records'),
          _SummaryMetric(label: text.t('天数'), value: '$days'),
          _SummaryMetric(
            label: text.t('花费'),
            value: '¥${total.toStringAsFixed(0)}',
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.records,
    required this.onTap,
  });

  final List<DrinkBudgetRecord> records;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 5),
          decoration: BoxDecoration(
            color: records.isEmpty
                ? context.siponColors.subtleSurface
                : context.siponColors.brandSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: records.isEmpty
                  ? Theme.of(context).colorScheme.outlineVariant
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: records.isEmpty
                    ? const SizedBox.shrink()
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          for (
                            var index = 0;
                            index < records.take(3).length;
                            index++
                          )
                            Transform.translate(
                              offset: Offset((index - 1) * 8, index * 5),
                              child: DrinkSticker(
                                record: records[index],
                                size: 34,
                                rotation: (index - 1) * 0.12,
                              ),
                            ),
                          if (records.length > 3)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '+${records.length - 3}',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onPrimary,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
