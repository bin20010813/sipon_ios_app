import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'harmony_platform.dart';

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
  Position? _lastDevicePosition;

  String get city => _city;
  String get province => _province;
  bool get initialized => _initialized;
  bool get manualSelection => _manualSelection;
  bool get locationAttempted => _locationAttempted;
  SiponLocationPoint? get detectedPosition => _detectedPosition;

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
    return result.city;
  }

  /// 供位置选择器进入时自动定位：返回带状态的结果，UI 据此提示手动选择。
  /// 打卡优先复用近期且精度合格的设备位置；不使用城市中心代替。
  Future<SiponLocateResult> locateCurrentCity({
    SiponLocationPurpose purpose = SiponLocationPurpose.citySuggestion,
  }) async {
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

      Position? recentPosition;
      if (purpose == SiponLocationPurpose.checkIn) {
        // 部分平台未提供系统缓存，仍可复用 App 刚取得的合格设备位置。
        if (_usableCheckInPosition(_lastDevicePosition)) {
          recentPosition = _lastDevicePosition;
        } else {
          try {
            final cached = await Geolocator.getLastKnownPosition().timeout(
              const Duration(milliseconds: 500),
            );
            if (_usableCheckInPosition(cached)) {
              recentPosition = cached;
            }
          } catch (_) {
            // 缓存不支持或读取超时时，继续获取实时定位。
          }
        }
      }

      final accuracy = purpose == SiponLocationPurpose.checkIn
          ? LocationAccuracy.high
          : LocationAccuracy.low;
      final timeLimit = purpose == SiponLocationPurpose.checkIn
          ? const Duration(seconds: 5)
          : const Duration(seconds: 3);
      final settings = defaultTargetPlatform == TargetPlatform.android
          ? AndroidSettings(accuracy: accuracy, timeLimit: timeLimit)
          : LocationSettings(accuracy: accuracy, timeLimit: timeLimit);

      Position position;
      try {
        position =
            recentPosition ??
            await Geolocator.getCurrentPosition(locationSettings: settings);
      } catch (_) {
        if (defaultTargetPlatform != TargetPlatform.android ||
            !await Geolocator.isLocationServiceEnabled() ||
            !await _hasLocationPermission()) {
          rethrow;
        }
        // GMS 路径报错或超时时，显式尝试系统 LocationManager。
        position = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: accuracy,
            timeLimit: const Duration(seconds: 3),
            forceLocationManager: true,
          ),
        );
      }

      if (!_validCoordinates(position)) {
        return const SiponLocateResult(status: SiponLocateStatus.failed);
      }

      _lastDevicePosition = position;
      var point = SiponLocationPoint(position.longitude, position.latitude);
      if (isHarmonyOS) {
        // Device GPS is WGS-84. Business map coordinates use Map Kit's
        // regional datum; never apply this conversion again in the map view.
        final converted = await harmonyServices
            .invokeMapMethod<String, Object?>('convertDeviceLocation', {
              'lng': position.longitude,
              'lat': position.latitude,
            });
        if (converted?['lng'] is! num || converted?['lat'] is! num) {
          return const SiponLocateResult(status: SiponLocateStatus.failed);
        }
        point = SiponLocationPoint(
          (converted!['lng']! as num).toDouble(),
          (converted['lat']! as num).toDouble(),
        );
      }
      _detectedPosition = point;

      final city = _nearestKnownCity(position.latitude, position.longitude);
      if (city == null) {
        return SiponLocateResult(
          status: SiponLocateStatus.failed,
          position: point,
        );
      }
      return SiponLocateResult(
        status: SiponLocateStatus.success,
        city: city,
        position: point,
      );
    } catch (_) {
      return const SiponLocateResult(status: SiponLocateStatus.failed);
    }
  }

  Future<bool> _hasLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  bool _usableCheckInPosition(Position? position) {
    if (position == null) return false;
    final age = DateTime.now().difference(position.timestamp);
    return !age.isNegative &&
        age <= const Duration(minutes: 2) &&
        position.accuracy.isFinite &&
        position.accuracy > 0 &&
        position.accuracy <= 100 &&
        _validCoordinates(position);
  }

  bool _validCoordinates(Position position) =>
      position.longitude.isFinite &&
      position.latitude.isFinite &&
      position.longitude >= -180 &&
      position.longitude <= 180 &&
      position.latitude >= -90 &&
      position.latitude <= 90;

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

enum SiponLocationPurpose { citySuggestion, checkIn }

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
