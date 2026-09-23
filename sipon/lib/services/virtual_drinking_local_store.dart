import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sipon_auth_service.dart';
import 'virtual_drinking_models.dart';

/// 虚拟体验的数据单独存储，不进入真实饮酒记账。
class VirtualDrinkingLocalStore {
  VirtualDrinkingLocalStore({String? scope})
    : _scope = scope ?? _currentAccountScope();

  final String _scope;

  static String _currentAccountScope() {
    final id = SiponAuthService.instance.session?.user['id'];
    return id == null ? 'guest' : 'user_$id';
  }

  String get _preferenceKey => 'virtual_drinking_preferences_$_scope';
  String get _countKey => 'virtual_drinking_daily_count_$_scope';

  Future<VirtualDrinkingPreference?> loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_preferenceKey);
    if (raw == null) return null;
    try {
      return VirtualDrinkingPreference.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> savePreference(VirtualDrinkingPreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, jsonEncode(preference.toJson()));
  }

  Future<int> loadTodayCount(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_countKey);
    if (value == null) return 0;
    try {
      final map = jsonDecode(value);
      if (map is Map && map['date'] == _day(now) && map['count'] is int) {
        return (map['count'] as int).clamp(0, 1000000);
      }
    } on FormatException {
      // Ignore a damaged local counter and start a new day at zero.
    }
    return 0;
  }

  Future<void> saveTodayCount(DateTime now, int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _countKey,
      jsonEncode({'date': _day(now), 'count': count}),
    );
  }

  static String _day(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
