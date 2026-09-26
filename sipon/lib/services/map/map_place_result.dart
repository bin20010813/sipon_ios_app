import 'map_viewport.dart';

/// Apple Maps address or place; it is never treated as an existing bar.
class MapPlaceResult {
  const MapPlaceResult({
    required this.name,
    required this.address,
    required this.city,
    required this.location,
  });

  final String name;
  final String address;
  final String city;
  final MapLatLng location;

  static MapPlaceResult? fromPayload(Object? value) {
    if (value is! Map) return null;
    final name = value['name'];
    final address = value['address'];
    final city = value['city'];
    final latitude = value['lat'];
    final longitude = value['lng'];
    if (name is! String ||
        name.trim().isEmpty ||
        latitude is! num ||
        longitude is! num) {
      return null;
    }
    final lat = latitude.toDouble();
    final lng = longitude.toDouble();
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
      return null;
    }
    return MapPlaceResult(
      name: name.trim(),
      address: address is String ? address.trim() : '',
      city: city is String ? city.trim() : '',
      location: MapLatLng(latitude: lat, longitude: lng),
    );
  }
}
