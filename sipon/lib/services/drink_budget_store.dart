import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sipon_api_service.dart';

/// 一条饮酒记账记录。
///
/// [id] 是本地生成的稳定标识，同时作为后端 `clientRecordId` 用于幂等重试；
/// [serverId] 是同步成功后后端返回的记录 id，为 null 表示尚未同步。
class DrinkBudgetRecord {
  DrinkBudgetRecord({
    String? id,
    required this.date,
    required this.amount,
    required this.drinkType,
    required this.place,
    this.cups = 1,
    this.rating = 0,
    this.note = '',
    this.serverId,
  }) : id = id ??
            '${date.millisecondsSinceEpoch}_${(amount * 100).toInt()}_${Random().nextInt(1 << 32)}';

  final String id;
  final DateTime date;
  final double amount;
  final String drinkType;
  final String place;
  final int cups;
  final int rating;
  final String note;

  /// 后端记录 id；为 null 表示这条记录只存在本地，等待同步。
  final int? serverId;

  /// 生成一个替换了 [serverId] 的副本，其余字段保持不变。
  DrinkBudgetRecord copyWithServerId(int? serverId) {
    return DrinkBudgetRecord(
      id: id,
      date: date,
      amount: amount,
      drinkType: drinkType,
      place: place,
      cups: cups,
      rating: rating,
      note: note,
      serverId: serverId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.millisecondsSinceEpoch,
        'amount': amount,
        'drinkType': drinkType,
        'place': place,
        'cups': cups,
        'rating': rating,
        'note': note,
        'serverId': serverId,
      };

  factory DrinkBudgetRecord.fromJson(Map<String, dynamic> json) {
    return DrinkBudgetRecord(
      id: json['id'] as String?,
      date: DateTime.fromMillisecondsSinceEpoch(json['date'] as int),
      amount: (json['amount'] as num).toDouble(),
      drinkType: (json['drinkType'] as String?) ?? '',
      place: (json['place'] as String?) ?? '',
      cups: (json['cups'] as int?) ?? 1,
      rating: (json['rating'] as int?) ?? 0,
      note: (json['note'] as String?) ?? '',
      serverId: (json['serverId'] as num?)?.toInt(),
    );
  }

  /// 转成后端 `DrinkRecordRequest`。
  ///
  /// 注意：后端当前版本携带 `occurredAt` 会触发 500，修复前只发 `occurredOn`。
  Map<String, Object?> toApiRequest() {
    return {
      'clientRecordId': id,
      'occurredOn':
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'timezone': 'Asia/Shanghai',
      'place': place,
      'amount': amount,
      'currency': 'CNY',
      'drinkType': drinkType,
      'cups': cups,
      'rating': rating,
      if (note.isNotEmpty) 'note': note,
    };
  }

  /// 从后端 `DrinkRecord` 响应还原本地记录；时间字段优先 `occurredOn`。
  factory DrinkBudgetRecord.fromApiJson(Map<String, dynamic> json) {
    final occurredOn = json['occurredOn']?.toString();
    final occurredAt = json['occurredAt']?.toString();
    final parsedDate =
        (occurredOn != null ? DateTime.tryParse(occurredOn) : null) ??
            (occurredAt != null ? DateTime.tryParse(occurredAt)?.toLocal() : null);
    final serverId = (json['id'] as num?)?.toInt();
    return DrinkBudgetRecord(
      id: json['clientRecordId']?.toString() ??
          (serverId != null ? 'server-$serverId' : null),
      date: parsedDate ?? DateTime.now(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      drinkType: json['drinkType']?.toString() ?? '',
      place: json['place']?.toString() ?? '',
      cups: (json['cups'] as num?)?.toInt() ?? 1,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      note: json['note']?.toString() ?? '',
      serverId: serverId,
    );
  }
}

class DrinkBudgetMonth {
  const DrinkBudgetMonth(this.year, this.month);

  factory DrinkBudgetMonth.now() {
    final now = DateTime.now();
    return DrinkBudgetMonth(now.year, now.month);
  }

  factory DrinkBudgetMonth.previous() {
    final now = DateTime.now();
    return now.month == 1
        ? DrinkBudgetMonth(now.year - 1, 12)
        : DrinkBudgetMonth(now.year, now.month - 1);
  }

  final int year;
  final int month;

  bool contains(DateTime date) => date.year == year && date.month == month;
}

/// 饮酒账本：本地优先 + 后台同步。
///
/// 所有写操作先落 SharedPreferences 保证弱网可用，再尽力同步后端；
/// [ensureSynced] 在登录态恢复或进入相关页面时做一次全量合并，
/// 合并以服务端记录为准，本地仅作缓存。同步失败不抛错、不阻塞 UI，
/// 通过 [hasPendingSync] 让页面提示「待同步」。
class DrinkBudgetStore extends ChangeNotifier {
  DrinkBudgetStore._({SiponApiService? api})
    : _api = api ?? SiponApiService();

  static final DrinkBudgetStore instance = DrinkBudgetStore._();

  static const String _budgetKey = 'drink_budget_monthly';
  static const String _recordsKey = 'drink_budget_records';
  static const double _defaultBudget = 1400.0;

  final SiponApiService _api;

  double _monthlyBudget = _defaultBudget;
  List<DrinkBudgetRecord> _records = const [];
  bool _loaded = false;
  bool _syncing = false;

  double get monthlyBudget => _monthlyBudget;
  List<DrinkBudgetRecord> get records => List.unmodifiable(_records);

  /// 是否存在尚未同步到后端的记录。
  bool get hasPendingSync => _records.any((record) => record.serverId == null);

  List<DrinkBudgetRecord> recordsOf(DrinkBudgetMonth month) {
    return _records.where((record) => month.contains(record.date)).toList();
  }

  double expenseOf(DrinkBudgetMonth month) {
    var total = 0.0;
    for (final record in _records) {
      if (month.contains(record.date)) {
        total += record.amount;
      }
    }
    return total;
  }

  double get currentMonthExpense => expenseOf(DrinkBudgetMonth.now());
  double get previousMonthExpense => expenseOf(DrinkBudgetMonth.previous());
  double get remaining => _monthlyBudget - currentMonthExpense;

  double get monthDeltaRatio {
    final previous = previousMonthExpense;
    if (previous <= 0) {
      return 0;
    }
    return (currentMonthExpense - previous) / previous;
  }

  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _monthlyBudget = prefs.getDouble(_budgetKey) ?? _defaultBudget;
    final raw = prefs.getString(_recordsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _records = decoded
            .map((item) => DrinkBudgetRecord.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _records = const [];
      }
    }
    _loaded = true;
  }

  /// 与后端做一次全量合并：先推送本地未同步记录，再拉取服务端记录覆盖本地，
  /// 最后同步当月预算。任何一步失败都静默收尾，留待下次重试。
  Future<void> ensureSynced() async {
    if (_syncing) {
      return;
    }
    _syncing = true;
    try {
      await ensureLoaded();
      await _pushPendingRecords();
      await _pullServerRecords();
      await _pullServerBudget();
    } on Exception {
      // 离线或未登录时同步失败属正常情况，本地数据不丢，下次再试。
    } finally {
      _syncing = false;
    }
  }

  /// 新增记录：先落库并通知页面，再尽力同步到后端。
  Future<void> addRecord(DrinkBudgetRecord record) async {
    _records = [record, ..._records];
    await _persistRecords();
    notifyListeners();
    await _pushRecord(record);
  }

  /// 删除记录：本地先删；已同步过的记录再尽力调用后端删除。
  Future<void> removeRecord(String id) async {
    final removed = _records.where((record) => record.id == id).firstOrNull;
    _records = _records.where((record) => record.id != id).toList();
    await _persistRecords();
    notifyListeners();

    final serverId = removed?.serverId;
    if (serverId != null) {
      try {
        await _api.deleteDrinkRecord(serverId);
      } on Exception {
        // 删除失败不阻塞本地操作；服务端残留数据在下次全量合并时被对齐。
      }
    }
  }

  /// 设置当月预算：先落本地，再尽力同步到后端（yyyy-MM 维度）。
  Future<void> setMonthlyBudget(double budget) async {
    _monthlyBudget = budget;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_budgetKey, budget);
    notifyListeners();

    try {
      await _api.setDrinkBudget(_currentMonthKey(), {
        'amount': budget,
        'currency': 'CNY',
      });
    } on Exception {
      // 预算同步失败保留本地值，下次 ensureSynced 再对齐。
    }
  }

  /// 推送所有未同步记录到后端，成功后回写 serverId。
  Future<void> _pushPendingRecords() async {
    final pending = _records.where((record) => record.serverId == null).toList();
    for (final record in pending) {
      await _pushRecord(record);
    }
  }

  /// 推送单条记录；clientRecordId 保证断网重传不会重复记账。
  Future<void> _pushRecord(DrinkBudgetRecord record) async {
    try {
      final response = await _api.createDrinkRecord(record.toApiRequest());
      final serverId = response is Map ? (response['id'] as num?)?.toInt() : null;
      if (serverId != null) {
        _records = [
          for (final item in _records)
            item.id == record.id ? item.copyWithServerId(serverId) : item,
        ];
        await _persistRecords();
        notifyListeners();
      }
    } on Exception {
      // 推送失败保留 serverId == null，等待下次 ensureSynced 重试。
    }
  }

  /// 拉取服务端全量记录并合并：以服务端为准，本地未同步的追加保留。
  Future<void> _pullServerRecords() async {
    final list = await _api.getDrinkRecords(from: '2000-01-01', to: _todayKey());
    final serverRecords = list
        .whereType<Map>()
        .map(
          (item) =>
              DrinkBudgetRecord.fromApiJson(item.cast<String, dynamic>()),
        )
        .toList();

    final merged = <String, DrinkBudgetRecord>{
      for (final record in serverRecords) record.id: record,
    };
    // 本地还未同步成功的记录（serverId == null）不在服务端结果里，追加保留。
    for (final record in _records) {
      if (record.serverId == null && !merged.containsKey(record.id)) {
        merged[record.id] = record;
      }
    }

    _records = merged.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    await _persistRecords();
    notifyListeners();
  }

  /// 拉取当月预算；后端未设置（404 等）时保留本地值。
  Future<void> _pullServerBudget() async {
    try {
      final response = await _api.getDrinkBudget(_currentMonthKey());
      if (response is Map) {
        final amount = (response['amount'] as num?)?.toDouble();
        if (amount != null) {
          _monthlyBudget = amount;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble(_budgetKey, amount);
          notifyListeners();
        }
      }
    } on Exception {
      // 未设置过预算时后端返回错误属预期，忽略即可。
    }
  }

  String _currentMonthKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _persistRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recordsKey,
      jsonEncode(_records.map((record) => record.toJson()).toList()),
    );
  }
}
