import 'package:sipon/features/profile/data/user_profile_data.dart';

class SiponNotification {
  const SiponNotification({
    required this.title,
    required this.body,
    required this.isProfileModeration,
    this.profileVersion,
    this.createdAt,
  });

  factory SiponNotification.fromJson(Object? value) {
    final map = _map(value);
    final payload = _map(map['payload']).isNotEmpty
        ? _map(map['payload'])
        : _map(map['data']);
    final type = _string(map['type']) ?? _string(map['category']) ?? '';
    final version =
        _integer(map['profileVersion']) ?? _integer(payload['profileVersion']);
    final isModeration =
        version != null ||
        (type.toLowerCase().contains('profile') &&
            (type.toLowerCase().contains('moderat') ||
                type.toLowerCase().contains('review')));
    return SiponNotification(
      title: _string(map['title']) ?? '系统通知',
      body:
          _string(map['body']) ??
          _string(map['content']) ??
          _string(map['message']) ??
          '',
      isProfileModeration: isModeration,
      profileVersion: version,
      createdAt: DateTime.tryParse(_string(map['createdAt']) ?? ''),
    );
  }

  final String title;
  final String body;
  final bool isProfileModeration;
  final int? profileVersion;
  final DateTime? createdAt;

  /// Old review results must not imply that the latest submitted profile passed.
  bool belongsTo(UserProfileData? profile) {
    if (!isProfileModeration) return true;
    return profileVersion != null && profileVersion == profile?.profileVersion;
  }
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};

String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
