import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sipon_region_data.dart';
import 'sipon_data_repository.dart';

class SiponCityController extends ChangeNotifier {
  static const String defaultCity = '上海';
  static const String defaultProvince = '上海市';
  static const String _storageKey = 'sipon.selected_city';
  static const String _provinceStorageKey = 'sipon.selected_province';

  SiponCityController({
    String initialCity = defaultCity,
    String initialProvince = defaultProvince,
  }) : _city = initialCity,
       _province = initialProvince;

  String _city;
  String _province;
  bool _initialized = false;
  bool _manualSelection = false;
  bool _locationAttempted = false;
  SiponLocationPoint? _detectedPosition;

  String get city => _city;
  String get province => _province;
  bool get initialized => _initialized;
  bool get manualSelection => _manualSelection;
  bool get locationAttempted => _locationAttempted;

  /// 手选城市以城市中心为查询锚点；自动定位时优先使用真实 WGS-84 坐标。
  SiponLocationPoint? get queryAnchor {
    if (!_manualSelection && _detectedPosition != null) {
      return _detectedPosition!;
    }
    final entry = siponFindCity(_city);
    if (entry == null) return null;
    return SiponLocationPoint(entry.longitude, entry.latitude);
  }

  /// 后端新增但本地行政区表尚未收录的城市，用该城市真实酒吧坐标作为锚点。
  Future<SiponLocationPoint?> resolveQueryAnchor() async {
    final known = queryAnchor;
    if (known != null) return known;
    final cityAtRequest = _city;
    try {
      final bars = await SiponDataRepository.instance.fetchHomeBars(
        city: cityAtRequest,
        limit: 1,
      );
      if (cityAtRequest != _city || bars.isEmpty) return null;
      final bar = bars.first;
      if (!bar.hasCoordinates) return null;
      return SiponLocationPoint(bar.longitude!, bar.latitude!);
    } catch (_) {
      return null;
    }
  }

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
      final savedProvince = preferences.getString(_provinceStorageKey)?.trim();
      if (savedProvince != null && savedProvince.isNotEmpty) {
        _province = savedProvince;
      } else if (_manualSelection) {
        // 老版本只存了城市：按内置表反查省份，保证选择器左侧能高亮。
        _province = siponFindProvinceOfCity(_city) ?? _province;
      }

      if (!_manualSelection) {
        final detected = await _detectCityByLocation();
        if (detected != null) {
          _city = detected.name;
          _province = siponFindProvinceOfCity(detected.name) ?? defaultProvince;
        } else {
          _detectedPosition = null;
          _city = defaultCity;
          _province = defaultProvince;
        }
      }
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> selectCity(String city, {String? province}) async {
    final normalizedCity = city.trim();
    if (normalizedCity.isEmpty) {
      return;
    }

    _city = normalizedCity;
    final normalizedProvince = province?.trim();
    _province = (normalizedProvince != null && normalizedProvince.isNotEmpty)
        ? normalizedProvince
        : (siponFindProvinceOfCity(normalizedCity) ?? _province);
    _manualSelection = true;
    _detectedPosition = null;
    notifyListeners();

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, normalizedCity);
    await preferences.setString(_provinceStorageKey, _province);
  }

  Future<SiponCityEntry?> _detectCityByLocation() async {
    final result = await locateCurrentCity();
    _detectedPosition = result.position;
    return result.city;
  }

  /// 供位置选择器进入时自动定位：返回带状态的结果，UI 据此提示手动选择。
  Future<SiponLocateResult> locateCurrentCity() async {
    _locationAttempted = true;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const SiponLocateResult(
          status: SiponLocateStatus.serviceDisabled,
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return const SiponLocateResult(
          status: SiponLocateStatus.permissionDenied,
        );
      }
      if (permission == LocationPermission.deniedForever) {
        return const SiponLocateResult(
          status: SiponLocateStatus.permissionDeniedForever,
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 3),
        ),
      );

      final city = _nearestKnownCity(position.latitude, position.longitude);
      if (city == null) {
        return const SiponLocateResult(status: SiponLocateStatus.failed);
      }
      return SiponLocateResult(
        status: SiponLocateStatus.success,
        city: city,
        position: SiponLocationPoint(position.longitude, position.latitude),
      );
    } catch (_) {
      return const SiponLocateResult(status: SiponLocateStatus.failed);
    }
  }

  SiponCityEntry? _nearestKnownCity(double latitude, double longitude) {
    SiponCityEntry? nearestCity;
    var nearestDistance = double.infinity;

    for (final province in siponProvinces) {
      for (final city in province.cities) {
        final distance = Geolocator.distanceBetween(
          latitude,
          longitude,
          city.latitude,
          city.longitude,
        );
        if (distance < nearestDistance) {
          nearestCity = city;
          nearestDistance = distance;
        }
      }
    }

    // 地级市全量表：相邻城市中心常相距 50~120km，阈值放宽到 120km；
    // 超出则视为不在国内，返回 null 由调用方回退默认城市。
    return nearestDistance <= 120000 ? nearestCity : null;
  }
}

enum SiponLocateStatus {
  success,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  failed,
}

class SiponLocateResult {
  const SiponLocateResult({required this.status, this.city, this.position});

  final SiponLocateStatus status;
  final SiponCityEntry? city;
  final SiponLocationPoint? position;
}

class SiponLocationPoint {
  const SiponLocationPoint(this.longitude, this.latitude);

  final double longitude;
  final double latitude;

  @override
  bool operator ==(Object other) =>
      other is SiponLocationPoint &&
      other.longitude == longitude &&
      other.latitude == latitude;

  @override
  int get hashCode => Object.hash(longitude, latitude);
}
