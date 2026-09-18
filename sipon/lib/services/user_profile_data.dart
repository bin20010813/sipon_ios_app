/// 用户资料接口的展示模型。
///
/// 当前联调文档只固定了资料基础字段，概览和公开主页的统计字段可能
/// 随后端版本略有不同；这里集中做兼容解析，避免把弱类型 Map 扩散到 UI。
class UserProfileData {
  const UserProfileData({
    this.id,
    this.username,
    this.email,
    this.displayName,
    this.avatarUrl,
    this.bio,
    this.city,
    this.level,
    this.locale,
    this.followersCount,
    this.followingCount,
    this.checkInCount,
    this.wishlistCount,
    this.routeCount,
    this.isFollowing,
  });

  factory UserProfileData.fromJson(Object? value) {
    final map = _asMap(value);
    final user = _asMap(map['user']);
    final source = user.isEmpty ? map : {...map, ...user};
    final overview = _asMap(map['overview']);

    int? count(List<String> keys) =>
        _readInt(source, keys) ?? _readInt(overview, keys);

    return UserProfileData(
      id: _readInt(source, const ['id', 'userId']),
      username: _readString(source, const ['username', 'handle']),
      email: _readString(source, const ['email']),
      displayName: _readString(source, const [
        'displayName',
        'nickname',
        'name',
      ]),
      avatarUrl: _readString(source, const [
        'avatarUrl',
        'avatar',
        'avatarImageUrl',
      ]),
      bio: _readString(source, const ['bio', 'introduction', 'description']),
      city: _readString(source, const ['city', 'location']),
      level: _readInt(source, const ['level']),
      locale: _readString(source, const ['locale']),
      followersCount: count(const [
        'followersCount',
        'followerCount',
        'followers',
      ]),
      followingCount: count(const [
        'followingCount',
        'followingsCount',
        'following',
      ]),
      checkInCount: count(const [
        'checkInCount',
        'checkInsCount',
        'checkinsCount',
      ]),
      wishlistCount: count(const ['wishlistCount', 'wishCount']),
      routeCount: count(const ['routeCount', 'routesCount']),
      isFollowing: _readBool(source, const [
        'isFollowing',
        'following',
        'viewerFollowing',
        'followedByViewer',
      ]),
    );
  }

  final int? id;
  final String? username;
  final String? email;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final String? city;
  final int? level;
  final String? locale;
  final int? followersCount;
  final int? followingCount;
  final int? checkInCount;
  final int? wishlistCount;
  final int? routeCount;
  final bool? isFollowing;

  String get name {
    final value = displayName ?? username ?? email;
    return value == null || value.trim().isEmpty ? 'Sipon 用户' : value.trim();
  }

  UserProfileData mergeOverview(Object? overview) => UserProfileData.fromJson({
    'id': id,
    'username': username,
    'email': email,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'bio': bio,
    'city': city,
    'level': level,
    'locale': locale,
    'isFollowing': isFollowing,
    'overview': overview,
  });
}

Map<String, dynamic> _asMap(Object? value) => value is Map
    ? value.map((key, item) => MapEntry(key.toString(), item))
    : const {};

String? _readString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value == null) continue;
    final result = value.toString().trim();
    if (result.isNotEmpty) return result;
  }
  return null;
}

int? _readInt(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

bool? _readBool(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is bool) return value;
    if (value is String) {
      if (value.toLowerCase() == 'true') return true;
      if (value.toLowerCase() == 'false') return false;
    }
  }
  return null;
}
