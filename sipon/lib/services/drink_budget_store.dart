import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.millisecondsSinceEpoch,
        'amount': amount,
        'drinkType': drinkType,
        'place': place,
        'cups': cups,
        'rating': rating,
        'note': note,
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

class DrinkBudgetStore extends ChangeNotifier {
  DrinkBudgetStore._();

  static final DrinkBudgetStore instance = DrinkBudgetStore._();

  static const String _budgetKey = 'drink_budget_monthly';
  static const String _recordsKey = 'drink_budget_records';
  static const double _defaultBudget = 1400.0;

  double _monthlyBudget = _defaultBudget;
  List<DrinkBudgetRecord> _records = const [];
  bool _loaded = false;

  double get monthlyBudget => _monthlyBudget;
  List<DrinkBudgetRecord> get records => List.unmodifiable(_records);

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

  Future<void> addRecord(DrinkBudgetRecord record) async {
    _records = [record, ..._records];
    await _persistRecords();
    notifyListeners();
  }

  Future<void> removeRecord(String id) async {
    _records = _records.where((record) => record.id != id).toList();
    await _persistRecords();
    notifyListeners();
  }

  Future<void> setMonthlyBudget(double budget) async {
    _monthlyBudget = budget;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_budgetKey, budget);
    notifyListeners();
  }

  Future<void> _persistRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recordsKey,
      jsonEncode(_records.map((record) => record.toJson()).toList()),
    );
  }
}
