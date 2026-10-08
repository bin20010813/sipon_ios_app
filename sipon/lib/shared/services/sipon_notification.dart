import 'dart:convert';

import 'package:sipon/features/profile/data/user_profile_data.dart';

class SiponNotification {
  const SiponNotification({
    required this.title,
    required this.body,
    this.id,
    this.type = '',
    this.isProfileModeration = false,
    this.profileVersion,
    this.createdAt,
    this.readAt,
    this.target = const {},
  });

  factory SiponNotification.fromJson(Object? value) {
    final map = _map(value);
    final target = {
      ..._map(map['target']),
      ..._map(map['data']),
      ..._map(map['payload']),
    };
    final type = _string(map['type']) ?? _string(map['category']) ?? '';
    final version =
        _integer(map['profileVersion']) ?? _integer(target['profileVersion']);
    return SiponNotification(
      id: _integer(map['id']),
      type: type,
      title: _string(map['title']) ?? '系统通知',
      body:
          _string(map['body']) ??
          _string(map['content']) ??
          _string(map['message']) ??
          '',
      isProfileModeration: version != null || type == 'profile_review',
      profileVersion: version,
      createdAt: DateTime.tryParse(_string(map['createdAt']) ?? ''),
      readAt: DateTime.tryParse(_string(map['readAt']) ?? ''),
      target: target,
    );
  }

  final int? id;
  final String type;
  final String title;
  final String body;
  final bool isProfileModeration;
  final int? profileVersion;
  final DateTime? createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> target;

  bool get isUnread => id != null && readAt == null;
  bool get isSocial => type == 'check_in_like' || type == 'check_in_comment';
  bool get isReview => isProfileModeration || type.endsWith('_review');
  int? get checkInId => _integer(target['checkInId']);
  int? get commentId => _integer(target['commentId']);
  int? get routeId => _integer(target['routeId']);
  int? get contentVersion => _integer(target['contentVersion']);

  SiponNotification asRead() => SiponNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    isProfileModeration: isProfileModeration,
    profileVersion: profileVersion,
    createdAt: createdAt,
    readAt: readAt ?? DateTime.now(),
    target: target,
  );

  /// An old review must not imply that the latest submitted profile passed.
  bool belongsTo(UserProfileData? profile) =>
      !isProfileModeration ||
      (profileVersion != null && profileVersion == profile?.profileVersion);
}

Map<String, dynamic> _map(Object? value) {
  if (value is String) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      return const {};
    }
  }
  return value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : const {};
}

String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
