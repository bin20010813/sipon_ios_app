part of '../pages/profile_page.dart';

class BudgetBillPage extends StatelessWidget {
  const BudgetBillPage({super.key, this.onDeleted});

  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // 底部不进安全区：内容与背景延伸到屏幕底部，小白条区域由
        // 列表自身的 padding 预留，避免底部留出一段不参与滚动的白边。
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: _BudgetBillBody(onDeleted: onDeleted),
          ),
        ),
      ),
    );
  }
}

class _BudgetBillBody extends StatefulWidget {
  const _BudgetBillBody({this.onDeleted});

  final VoidCallback? onDeleted;

  @override
  State<_BudgetBillBody> createState() => _BudgetBillBodyState();
}

class _BudgetBillBodyState extends State<_BudgetBillBody> {
  static const _chartColors = [
    Color(0xFF9A3D78),
    Color(0xFFEE8E51),
    Color(0xFF477BC8),
    Color(0xFF3FA66A),
    Color(0xFFC2A43A),
  ];

  final DrinkBudgetStore _store = DrinkBudgetStore.instance;
  late DateTime _selectedDate;
  _BillPeriod _period = _BillPeriod.month;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _store.addListener(_onStoreChanged);
    // 进入账单页时与后端对齐一次，保证跨设备数据一致。
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

  Future<void> _pickDate() async {
    final selected = await showDialog<DateTime>(
      context: context,
      builder: (_) => _BillDatePickerDialog(
        initialDate: _selectedDate,
        records: _store.records,
        period: _period,
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedDate = selected);
    }
  }

  String _formatSelectedDate(SiponAppText text) {
    final date = _selectedDate;
    if (_period == _BillPeriod.year) {
      return text.isZh ? '${date.year}年' : '${date.year}';
    }

    if (_period == _BillPeriod.month) {
      return text.isZh
          ? '${date.year}年${date.month}月'
          : '${date.month}/${date.year}';
    }

    if (_period == _BillPeriod.week) {
      final weekStart = date.subtract(Duration(days: date.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));
      if (text.isZh) {
        if (weekStart.month == weekEnd.month) {
          return '${weekStart.year}年${weekStart.month}月${weekStart.day}日至${weekEnd.day}日';
        }
        return '${weekStart.year}年${weekStart.month}月${weekStart.day}日至${weekEnd.month}月${weekEnd.day}日';
      }
      return '${weekStart.month}/${weekStart.day} - ${weekEnd.month}/${weekEnd.day}';
    }

    return text.isZh ? '${date.year}年' : '${date.year}';
  }

  String _formatDate(DateTime date, SiponAppText text) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) {
      return text.t('今天');
    }

    if (text.isZh) {
      return '${date.month}月${date.day}日';
    }

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
    return '${months[date.month - 1]} ${date.day}';
  }

  List<DrinkBudgetRecord> _recordsForPeriod() {
    final dayStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final weekStart = dayStart.subtract(Duration(days: dayStart.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final month = DrinkBudgetMonth(_selectedDate.year, _selectedDate.month);
    final records = _store.records.where((record) {
      switch (_period) {
        case _BillPeriod.year:
          return record.date.year == _selectedDate.year;
        case _BillPeriod.week:
          return !record.date.isBefore(weekStart) &&
              record.date.isBefore(weekEnd);
        case _BillPeriod.month:
          return month.contains(record.date);
      }
    }).toList();
    records.sort((a, b) => b.date.compareTo(a.date));
    return records;
  }

  Map<String, double> _categoryExpenses(List<DrinkBudgetRecord> records) {
    final expenses = <String, double>{};
    for (final record in records) {
      expenses.update(
        record.drinkType,
        (value) => value + record.amount,
        ifAbsent: () => record.amount,
      );
    }
    final sorted = expenses.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  int _activeDays(List<DrinkBudgetRecord> records) {
    return records
        .map(
          (record) =>
              DateTime(record.date.year, record.date.month, record.date.day),
        )
        .toSet()
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final records = _recordsForPeriod();
    final total = records.fold<double>(0, (sum, record) => sum + record.amount);
    final categoryExpenses = _categoryExpenses(records);
    final budgetProgress = _store.monthlyBudget <= 0
        ? 0.0
        : (total / _store.monthlyBudget).clamp(0.0, 1.0);

    final bottomSafeInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      // 底部留白放在滚动内容内部（见最后一个 sliver），而不是包住
      // CustomScrollView：视口延伸到屏幕底部，滚动时内容能自然滑入
      // 小白条区域，不再留出一条不参与滚动的白边。
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          tooltip: text.back,
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                      Text(
                        text.t('统计'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: ProfilePage._ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: text.t('更多'),
                          onPressed: () {},
                          icon: const Icon(Icons.more_vert_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 0),
                Center(
                  child: Transform.translate(
                    offset: const Offset(8, 0),
                    child: TextButton(
                      onPressed: _pickDate,
                      style: TextButton.styleFrom(
                        foregroundColor: ProfilePage._ink,
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatSelectedDate(text),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(width: 1),
                          const Icon(Icons.arrow_drop_down_rounded, size: 23),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _BillPeriodSelector(
                  period: _period,
                  text: text,
                  onChanged: (period) => setState(() => _period = period),
                ),
                const SizedBox(height: 16),
                DrinkStickerGravityPool(
                  records: records,
                  height: 220,
                  onStickerTap: (record) => showModalBottomSheet<void>(
                    context: context,
                    useSafeArea: true,
                    showDragHandle: true,
                    backgroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(22),
                      ),
                    ),
                    builder: (_) => _BudgetRecordDetailSheet(
                      record: record,
                      dateText: _formatDate(record.date, text),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                _BillSummary(
                  headline: '${_period.label(text)}${text.t('支出')}',
                  total: total,
                  budget: _store.monthlyBudget,
                  progress: budgetProgress,
                  recordCount: records.length,
                  activeDays: _activeDays(records),
                ),
                const SizedBox(height: 24),
                Text(
                  text.t('消费构成'),
                  style: const TextStyle(
                    color: ProfilePage._ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                _BillCategoryChart(
                  expenses: categoryExpenses,
                  colors: _chartColors,
                  text: text,
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_period.label(text)}${text.t('明细')}',
                        style: const TextStyle(
                          color: ProfilePage._ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    Text(
                      '${records.length}${text.t('笔')}',
                      style: const TextStyle(
                        color: ProfilePage._muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          if (records.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 42),
                child: Center(
                  child: Text(
                    text.noRecords,
                    style: const TextStyle(
                      color: ProfilePage._muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
            )
          else
            SliverList.separated(
              itemCount: records.length,
              itemBuilder: (_, index) {
                final record = records[index];
                return _BudgetRecordTile(
                  record: record,
                  dateText: _formatDate(record.date, text),
                  onDeleted: () async {
                    await _store.removeRecord(record.id);
                    widget.onDeleted?.call();
                  },
                );
              },
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: ProfilePage._line),
            ),
          // 尾部留白 = 原有间距 32 + 底部安全区，保证静止时明细不被
          // 小白条遮挡；滚动中该区域随内容一起滑入滑出。
          SliverToBoxAdapter(child: SizedBox(height: 32 + bottomSafeInset)),
        ],
      ),
    );
  }
}

class _BillDatePickerDialog extends StatefulWidget {
  const _BillDatePickerDialog({
    required this.initialDate,
    required this.records,
    this.period = _BillPeriod.month,
  });

  final DateTime initialDate;
  final List<DrinkBudgetRecord> records;
  final _BillPeriod period;

  @override
  State<_BillDatePickerDialog> createState() => _BillDatePickerDialogState();
}

class _BillDatePickerDialogState extends State<_BillDatePickerDialog> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
    _month = DateTime(_selected.year, _selected.month);
  }

  bool _hasRecord(int day) {
    return widget.records.any(
      (record) =>
          record.date.year == _month.year &&
          record.date.month == _month.month &&
          record.date.day == day,
    );
  }

  void _changeMonth(int offset) {
    final next = DateTime(_month.year, _month.month + offset);
    if (next.isAfter(DateTime(DateTime.now().year, DateTime.now().month))) {
      return;
    }
    setState(() => _month = next);
  }

  Widget _buildYearPicker(SiponAppText text) {
    final now = DateTime.now();
    final years = [
      for (var year = now.year; year >= now.year - 11; year--) year,
    ];
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text.t('选择年份'),
              style: const TextStyle(
                color: ProfilePage._ink,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: years.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisExtent: 48,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (_, index) {
                final year = years[index];
                final selected = year == widget.initialDate.year;
                return InkWell(
                  onTap: () => Navigator.of(context).pop(DateTime(year)),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? ProfilePage._brand
                          : const Color(0xFFF5F0F4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$year',
                      style: TextStyle(
                        color: selected ? Colors.white : ProfilePage._ink,
                        fontSize: 14,
                        fontWeight: selected
                            ? FontWeight.w900
                            : FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(text.cancel),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    if (widget.period == _BillPeriod.year) {
      return _buildYearPicker(text);
    }
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday;
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '${_month.year}年${_month.month}月',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: ProfilePage._ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            Row(
              children: [
                for (final label in ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: ProfilePage._muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
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
              itemCount: firstWeekday - 1 + days,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: 42,
              ),
              itemBuilder: (_, index) {
                if (index < firstWeekday - 1) {
                  return const SizedBox.shrink();
                }
                final day = index - firstWeekday + 2;
                final date = DateTime(_month.year, _month.month, day);
                final selected =
                    date.year == _selected.year &&
                    date.month == _selected.month &&
                    date.day == _selected.day;
                final hasRecord = _hasRecord(day);
                return InkWell(
                  onTap: () => Navigator.of(context).pop(date),
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? ProfilePage._brand : null,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$day',
                          style: TextStyle(
                            color: selected ? Colors.white : ProfilePage._ink,
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w900
                                : FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: hasRecord
                              ? ProfilePage._brand
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(text.cancel),
            ),
          ],
        ),
      ),
    );
  }
}

enum _BillPeriod { week, month, year }

extension on _BillPeriod {
  String label(SiponAppText text) {
    switch (this) {
      case _BillPeriod.year:
        return text.t('本年');
      case _BillPeriod.week:
        return text.t('本周');
      case _BillPeriod.month:
        return text.t('本月');
      case _BillPeriod.week:
        return text.t('本周');
    }
  }
}

class _BillPeriodSelector extends StatelessWidget {
  const _BillPeriodSelector({
    required this.period,
    required this.text,
    required this.onChanged,
  });

  final _BillPeriod period;
  final SiponAppText text;
  final ValueChanged<_BillPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          for (final option in _BillPeriod.values)
            Expanded(
              child: _BillPeriodOption(
                label: switch (option) {
                  _BillPeriod.week => text.t('周'),
                  _BillPeriod.month => text.t('月'),
                  _BillPeriod.year => text.t('年'),
                },
                selected: period == option,
                onTap: () => onChanged(option),
              ),
            ),
        ],
      ),
    );
  }
}

class _BillPeriodOption extends StatelessWidget {
  const _BillPeriodOption({
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
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: ProfilePage._ink,
                fontSize: 17,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BillSummary extends StatelessWidget {
  const _BillSummary({
    required this.headline,
    required this.total,
    required this.budget,
    required this.progress,
    required this.recordCount,
    required this.activeDays,
  });

  final String headline;
  final double total;
  final double budget;
  final double progress;
  final int recordCount;
  final int activeDays;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final average = activeDays == 0 ? 0.0 : total / activeDays;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF2DFEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            headline,
            style: const TextStyle(
              color: ProfilePage._muted,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatCurrency(total),
            style: const TextStyle(
              color: ProfilePage._brand,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFF2E6ED),
              valueColor: const AlwaysStoppedAnimation(ProfilePage._brand),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${text.t('预算')} ${_formatCurrency(budget)}  ·  ${text.t('剩余')} ${_formatCurrency(budget - total)}',
            style: const TextStyle(
              color: ProfilePage._muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFF0E3EB)),
          ),
          Row(
            children: [
              Expanded(
                child: _BillMetric(
                  label: text.t('记账笔数'),
                  value: '$recordCount',
                ),
              ),
              Container(
                width: 1,
                height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: const Color(0xFFF0E3EB),
              ),
              Expanded(
                child: _BillMetric(label: text.t('消费天数'), value: '$activeDays'),
              ),
              Container(
                width: 1,
                height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: const Color(0xFFF0E3EB),
              ),
              Expanded(
                child: _BillMetric(
                  label: text.t('日均消费'),
                  value: _formatCurrency(average),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillMetric extends StatelessWidget {
  const _BillMetric({required this.label, required this.value});

  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: ProfilePage._muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              color: ProfilePage._ink,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _DayExpense {
  const _DayExpense(this.date, this.amount);

  final DateTime date;
  final double amount;
}

class _BillCategoryChart extends StatelessWidget {
  const _BillCategoryChart({
    required this.expenses,
    required this.colors,
    required this.text,
  });

  final Map<String, double> expenses;
  final List<Color> colors;
  final SiponAppText text;

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return const _BillChartEmpty();
    }
    final total = expenses.values.fold<double>(0, (sum, value) => sum + value);
    final entries = expenses.entries.toList();
    if (entries.length > colors.length) {
      final otherTotal = entries
          .skip(colors.length - 1)
          .fold<double>(0, (sum, entry) => sum + entry.value);
      entries
        ..removeRange(colors.length - 1, entries.length)
        ..add(MapEntry('其他', otherTotal));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CustomPaint(
          size: const Size(116, 116),
          painter: _CategoryPiePainter(
            values: entries.map((entry) => entry.value).toList(),
            colors: colors,
          ),
          child: SizedBox(
            width: 116,
            height: 116,
            child: Center(
              child: Text(
                _formatCurrency(total),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: ProfilePage._ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: [
              for (var index = 0; index < entries.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colors[index % colors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          text.t(entries[index].key),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ProfilePage._ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      Text(
                        '${(entries[index].value / total * 100).round()}%',
                        style: const TextStyle(
                          color: ProfilePage._muted,
                          fontSize: 11,
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
    );
  }
}

class _BillChartEmpty extends StatelessWidget {
  const _BillChartEmpty();

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    return Container(
      height: 116,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text.t('暂无统计数据'),
        style: const TextStyle(
          color: ProfilePage._muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _CategoryPiePainter extends CustomPainter {
  const _CategoryPiePainter({required this.values, required this.colors});

  final List<double> values;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) {
      return;
    }
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.butt;
    var start = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      final sweep = values[index] / total * math.pi * 2;
      paint.color = colors[index % colors.length];
      canvas.drawArc(rect.deflate(9), start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _CategoryPiePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}

class _BudgetRecordTile extends StatelessWidget {
  const _BudgetRecordTile({
    required this.record,
    required this.dateText,
    required this.onDeleted,
  });

  final DrinkBudgetRecord record;
  final String dateText;
  final VoidCallback onDeleted;

  String _formatFullDate(DateTime date, SiponAppText text) {
    if (text.isZh) {
      return '${date.year}年${date.month}月${date.day}日';
    }

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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _showDetail(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _BudgetRecordDetailSheet(
        record: record,
        dateText: _formatFullDate(record.date, text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showDetail(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              DrinkSticker(record: record, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text.t(record.drinkType),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProfilePage._ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${text.t(record.place)} · $dateText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProfilePage._muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _formatCurrency(record.amount),
                style: const TextStyle(
                  color: ProfilePage._brand,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: onDeleted,
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: const Color(0xFFC7C1C6),
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(28, 28),
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BudgetRecordDetailSheet extends StatelessWidget {
  const _BudgetRecordDetailSheet({
    required this.record,
    required this.dateText,
  });

  final DrinkBudgetRecord record;
  final String dateText;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final note = record.note.trim();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DrinkSticker(record: record, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text.t('记录详情'),
                        style: const TextStyle(
                          color: ProfilePage._ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        text.t('本笔记账'),
                        style: const TextStyle(
                          color: ProfilePage._muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatCurrency(record.amount),
                  style: const TextStyle(
                    color: ProfilePage._brand,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _RecordDetailRow(
              label: text.t('酒款'),
              value: text.t(record.drinkType),
            ),
            _RecordDetailRow(label: text.t('地点'), value: text.t(record.place)),
            _RecordDetailRow(label: text.t('日期'), value: dateText),
            _RecordDetailRow(
              label: text.t('花费'),
              value: _formatCurrency(record.amount),
            ),
            _RecordDetailRow(
              label: text.t('杯数'),
              value: '${record.cups} ${text.t('杯')}',
            ),
            _RecordDetailRow(
              label: text.t('评分'),
              value: record.rating > 0 ? '${record.rating}/5' : '-',
            ),
            _RecordDetailRow(
              label: text.t('备注'),
              value: note.isEmpty ? '-' : note,
              alignTop: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordDetailRow extends StatelessWidget {
  const _RecordDetailRow({
    required this.label,
    required this.value,
    this.alignTop = false,
  });

  final String label;
  final String value;
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: alignTop
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: const TextStyle(
                color: ProfilePage._muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: ProfilePage._ink,
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
      ),
    );
  }
}
