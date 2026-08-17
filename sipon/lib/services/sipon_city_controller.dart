import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SiponCityController extends ChangeNotifier {
  static const String defaultCity = '上海';
  static const String _storageKey = 'sipon.selected_city';

  SiponCityController({String initialCity = defaultCity}) : _city = initialCity;

  String _city;
  bool _initialized = false;
  bool _manualSelection = false;
  bool _locationAttempted = false;

  String get city => _city;
  bool get initialized => _initialized;
  bool get manualSelection => _manualSelection;
  bool get locationAttempted => _locationAttempted;

  Future<void> load() async {
    if (_initialized) {
      return;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      final savedCity = preferences.getString(_storageKey)?.trim();
      if (savedCity != null && savedCity.isNotEmpty) {
        _city = savedCity;
        _manualSelection = true;
      }

      if (!_manualSelection) {
        _city = await _detectCityByLocation() ?? defaultCity;
      }
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> selectCity(String city) async {
    final normalizedCity = city.trim();
    if (normalizedCity.isEmpty) {
      return;
    }

    _city = normalizedCity;
    _manualSelection = true;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, normalizedCity);
  }

  Future<String?> _detectCityByLocation() async {
    _locationAttempted = true;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 3),
        ),
      );

      return _nearestKnownCity(position.latitude, position.longitude);
    } catch (_) {
      return null;
    }
  }

  String? _nearestKnownCity(double latitude, double longitude) {
    String? nearestCity;
    var nearestDistance = double.infinity;

    for (final city in _knownCityCenters.entries) {
      final distance = Geolocator.distanceBetween(
        latitude,
        longitude,
        city.value.latitude,
        city.value.longitude,
      );
      if (distance < nearestDistance) {
        nearestCity = city.key;
        nearestDistance = distance;
      }
    }

    return nearestDistance <= 80000 ? nearestCity : null;
  }
}

class _CityCenter {
  const _CityCenter({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

const Map<String, _CityCenter> _knownCityCenters = {
  '上海': _CityCenter(latitude: 31.2227, longitude: 121.4712),
  '北京': _CityCenter(latitude: 39.9042, longitude: 116.4074),
  '深圳': _CityCenter(latitude: 22.5431, longitude: 114.0579),
  '广州': _CityCenter(latitude: 23.1291, longitude: 113.2644),
  '成都': _CityCenter(latitude: 30.5728, longitude: 104.0668),
  '杭州': _CityCenter(latitude: 30.2741, longitude: 120.1551),
};
