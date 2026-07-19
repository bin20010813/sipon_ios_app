class SiponMapBounds {
  const SiponMapBounds({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });

  const SiponMapBounds.china() : west = 73, south = 18, east = 135, north = 54;

  final double west;
  final double south;
  final double east;
  final double north;

  Map<String, Object?> toQueryParameters(double zoom) {
    return {
      'west': west,
      'south': south,
      'east': east,
      'north': north,
      'zoom': zoom.clamp(0, 22),
    };
  }
}

class SiponBarMapResponse {
  const SiponBarMapResponse({required this.mode, required this.items});

  final String mode;
  final List<SiponBarMapItem> items;

  factory SiponBarMapResponse.fromJson(dynamic json) {
    if (json is List) {
      return SiponBarMapResponse(
        mode: 'bars',
        items: json
            .whereType<Map>()
            .map(
              (item) => SiponBarMapItem.fromJson(item.cast<String, dynamic>()),
            )
            .where((item) => item.hasCoordinates)
            .toList(growable: false),
      );
    }

    final map = _asMap(json);
    final data = _asMap(map['data']);
    final rawItems =
        _asList(map['items']) ??
        _asList(data['items']) ??
        _asList(data) ??
        const [];

    return SiponBarMapResponse(
      mode: _readString(map, ['mode']) ?? _readString(data, ['mode']) ?? 'bars',
      items: rawItems
          .whereType<Map>()
          .map((item) => SiponBarMapItem.fromJson(item.cast<String, dynamic>()))
          .where((item) => item.hasCoordinates)
          .toList(growable: false),
    );
  }
}

class SiponBarMapItem {
  const SiponBarMapItem({
    required this.id,
    required this.name,
    required this.longitude,
    required this.latitude,
    required this.cluster,
    required this.count,
    required this.kind,
    required this.rating,
    required this.address,
    required this.distance,
    required this.tags,
    required this.imageUrl,
  });

  final String id;
  final String name;
  final double? longitude;
  final double? latitude;
  final bool cluster;
  final int count;
  final String kind;
  final double rating;
  final String address;
  final String distance;
  final List<String> tags;
  final String? imageUrl;

  bool get hasCoordinates => longitude != null && latitude != null;

  factory SiponBarMapItem.fromJson(Map<String, dynamic> json) {
    final properties = _asMap(json['properties']);
    final geometry = _asMap(json['geometry']);
    final coordinates =
        _readCoordinates(json) ??
        _readCoordinates(properties) ??
        _readCoordinates(geometry);
    final cluster =
        _readBool(json, ['cluster', 'isCluster']) ??
        _readBool(properties, ['cluster', 'isCluster']) ??
        false;
    final count =
        _readInt(json, ['count', 'point_count']) ??
        _readInt(properties, ['count', 'point_count']) ??
        (cluster ? 0 : 1);
    final subtype =
        _readString(json, ['barSubtype', 'subtype']) ??
        _readString(properties, ['barSubtype', 'subtype']);
    final rawKind =
        subtype ??
        _readString(properties, ['kind', 'category', 'type', 'barType']) ??
        _readString(json, ['kind', 'category', 'barType', 'type']);
    final parsedTags =
        _readStringList(json, ['tags', 'labels', 'categories']) ??
        _readStringList(properties, ['tags', 'labels', 'categories']);
    final subtypeTags = subtype == null ? null : _splitTags(subtype);
    final tags = parsedTags ?? subtypeTags ?? const <String>[];
    final fallbackKind = _kindFromTags(tags);
    final kind = _normalizeKind(rawKind ?? fallbackKind);
    final name =
        _readString(json, ['name', 'barName', 'title']) ??
        _readString(properties, ['name', 'barName', 'title']) ??
        (cluster && count > 0 ? '$count 家酒吧' : '未命名酒吧');
    final id =
        _readString(json, ['id', 'barId', 'clusterId']) ??
        _readString(properties, ['id', 'barId', 'clusterId']) ??
        '$kind-${coordinates?.longitude ?? 0}-${coordinates?.latitude ?? 0}';

    return SiponBarMapItem(
      id: id,
      name: name,
      longitude: coordinates?.longitude,
      latitude: coordinates?.latitude,
      cluster: cluster,
      count: count,
      kind: kind,
      rating:
          _readDouble(json, ['rating', 'score', 'star']) ??
          _readDouble(properties, ['rating', 'score', 'star']) ??
          4.8,
      address:
          _readString(json, ['address', 'addr', 'locationText', 'city']) ??
          _readString(properties, [
            'address',
            'addr',
            'locationText',
            'city',
          ]) ??
          '地址待补充',
      distance:
          _readString(json, ['distance', 'distanceText']) ??
          _readString(properties, ['distance', 'distanceText']) ??
          _formatDistanceMeters(
            _readDouble(json, ['distanceMeters', 'distanceInMeters']) ??
                _readDouble(properties, ['distanceMeters', 'distanceInMeters']),
          ),
      tags: tags.isEmpty ? [_displayKind(kind)] : tags,
      imageUrl:
          _readString(json, ['imageUrl', 'image', 'cover', 'coverUrl']) ??
          _readString(properties, ['imageUrl', 'image', 'cover', 'coverUrl']),
    );
  }
}

class _Coordinates {
  const _Coordinates({required this.longitude, required this.latitude});

  final double longitude;
  final double latitude;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return value.cast<String, dynamic>();
  }

  return const {};
}

List<dynamic>? _asList(dynamic value) {
  if (value is List) {
    return value;
  }

  return null;
}

String? _readString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) {
      continue;
    }
    final text = value.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }
  }

  return null;
}

double? _readDouble(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }

  return null;
}

int? _readInt(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }

  return null;
}

bool? _readBool(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') {
        return true;
      }
      if (normalized == 'false') {
        return false;
      }
    }
  }

  return null;
}

List<String>? _readStringList(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is List) {
      final strings = value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (strings.isNotEmpty) {
        return strings;
      }
    }
    if (value is String) {
      final strings = _splitTags(value);
      if (strings.isNotEmpty) {
        return strings;
      }
    }
  }

  return null;
}

List<String> _splitTags(String value) {
  return value
      .split(RegExp(r'[|,，/、\s]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

_Coordinates? _readCoordinates(Map<String, dynamic> map) {
  final geometry = _asMap(map['geometry']);
  final directCoordinates = _asList(map['coordinates']);
  final geometryCoordinates = _asList(geometry['coordinates']);
  final coordinates = directCoordinates ?? geometryCoordinates ?? const [];

  if (coordinates.length >= 2) {
    final longitude = _toDouble(coordinates[0]);
    final latitude = _toDouble(coordinates[1]);
    if (longitude != null && latitude != null) {
      return _Coordinates(longitude: longitude, latitude: latitude);
    }
  }

  final nestedCoordinate = _asMap(map['coordinate']).isNotEmpty
      ? _asMap(map['coordinate'])
      : _asMap(map['center']);
  final longitude =
      _readDouble(map, ['longitude', 'lng', 'lon', 'x']) ??
      _readDouble(nestedCoordinate, ['longitude', 'lng', 'lon', 'x']);
  final latitude =
      _readDouble(map, ['latitude', 'lat', 'y']) ??
      _readDouble(nestedCoordinate, ['latitude', 'lat', 'y']);

  if (longitude == null || latitude == null) {
    return null;
  }

  return _Coordinates(longitude: longitude, latitude: latitude);
}

double? _toDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }

  return null;
}

String _normalizeKind(String rawKind) {
  final kind = rawKind.trim().toLowerCase();
  if (kind.contains('craft') || kind.contains('精酿') || kind.contains('beer')) {
    return 'craft';
  }
  if (kind.contains('bistro') || kind.contains('餐酒')) {
    return 'bistro';
  }
  if (kind.contains('party') || kind.contains('club') || kind.contains('派对')) {
    return 'party';
  }
  if (kind.contains('live') || kind.contains('音乐')) {
    return 'livehouse';
  }

  return 'pub';
}

String _kindFromTags(List<String> tags) {
  for (final tag in tags) {
    final normalized = _normalizeKind(tag);
    if (normalized != 'pub' || tag.contains('清吧')) {
      return normalized;
    }
  }

  return 'pub';
}

String _displayKind(String kind) {
  return switch (kind) {
    'craft' => '精酿',
    'bistro' => 'Bistro',
    'party' => '派对',
    'livehouse' => 'Livehouse',
    _ => '清吧',
  };
}

String _formatDistanceMeters(double? meters) {
  if (meters == null) {
    return '距离待计算';
  }
  if (meters >= 1000) {
    return '约${(meters / 1000).toStringAsFixed(1)}km';
  }

  return '约${meters.round()}m';
}
