import 'package:flutter/material.dart';

import '../services/sipon_api_config.dart';
import '../services/sipon_api_service.dart';
import '../services/user_profile_data.dart';

class PublicProfilePage extends StatefulWidget {
  const PublicProfilePage({
    super.key,
    required this.userId,
    this.isCurrentUser = false,
  });

  final int userId;
  final bool isCurrentUser;

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  final _api = SiponApiService();
  UserProfileData? _profile;
  Object? _error;
  bool _loading = true;
  bool _updatingFollow = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.getUserProfile(widget.userId);
      if (mounted) {
        setState(() => _profile = UserProfileData.fromJson(response));
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    final profile = _profile;
    if (profile == null || _updatingFollow || widget.isCurrentUser) return;
    setState(() => _updatingFollow = true);
    try {
      if (profile.isFollowing == true) {
        await _api.unfollowUser(widget.userId);
      } else {
        await _api.followUser(widget.userId);
      }
      await _load();
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('操作失败，请稍后重试。')));
    } finally {
      if (mounted) setState(() => _updatingFollow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('用户主页'), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || _profile == null
          ? _ProfileLoadError(onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                children: [
                  _ProfileContent(
                    profile: _profile!,
                    onFollow: _toggleFollow,
                    isCurrentUser: widget.isCurrentUser,
                    updatingFollow: _updatingFollow,
                  ),
                ],
              ),
            ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.profile,
    required this.onFollow,
    required this.isCurrentUser,
    required this.updatingFollow,
  });
  final UserProfileData profile;
  final VoidCallback onFollow;
  final bool isCurrentUser;
  final bool updatingFollow;

  @override
  Widget build(BuildContext context) {
    final stats = <_ProfileStat>[
      _ProfileStat('粉丝', profile.followersCount),
      _ProfileStat('关注', profile.followingCount),
      _ProfileStat('打卡', profile.checkInCount),
      if (profile.wishlistCount != null)
        _ProfileStat('想喝', profile.wishlistCount),
      if (profile.routeCount != null) _ProfileStat('路线', profile.routeCount),
    ];
    return Column(
      children: [
        _UserAvatar(url: profile.avatarUrl, size: 96),
        const SizedBox(height: 14),
        Text(
          profile.name,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (profile.username?.isNotEmpty == true) ...[
          const SizedBox(height: 4),
          Text(
            '@${profile.username}',
            style: const TextStyle(color: Color(0xFF8E8790)),
          ),
        ],
        if (profile.city?.isNotEmpty == true) ...[
          const SizedBox(height: 7),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 16,
                color: Color(0xFF8E8790),
              ),
              const SizedBox(width: 3),
              Text(
                profile.city!,
                style: const TextStyle(color: Color(0xFF6D666D)),
              ),
            ],
          ),
        ],
        if (profile.bio?.isNotEmpty == true) ...[
          const SizedBox(height: 16),
          Text(
            profile.bio!,
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.5, color: Color(0xFF4B464B)),
          ),
        ],
        if (!isCurrentUser) ...[
          const SizedBox(height: 20),
          SizedBox(
            width: 152,
            child: FilledButton(
              onPressed: updatingFollow ? null : onFollow,
              style: FilledButton.styleFrom(
                backgroundColor: profile.isFollowing == true
                    ? const Color(0xFFF0E9ED)
                    : const Color(0xFF9A3D78),
                foregroundColor: profile.isFollowing == true
                    ? const Color(0xFF6D5865)
                    : Colors.white,
              ),
              child: Text(
                updatingFollow
                    ? '处理中…'
                    : (profile.isFollowing == true ? '已关注' : '关注'),
              ),
            ),
          ),
        ],
        const SizedBox(height: 30),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFCF8FA),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              for (final stat in stats) Expanded(child: _StatTile(stat: stat)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileStat {
  const _ProfileStat(this.label, this.value);
  final String label;
  final int? value;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final _ProfileStat stat;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        stat.value?.toString() ?? '—',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      Text(
        stat.label,
        style: const TextStyle(color: Color(0xFF8E8790), fontSize: 12),
      ),
    ],
  );
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.url, required this.size});
  final String? url;
  final double size;
  @override
  Widget build(BuildContext context) {
    final value = url?.trim();
    final imageUrl = value == null || value.isEmpty
        ? null
        : SiponApiConfig.instance.resolveUri(value).toString();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xFFFFE4F1),
      backgroundImage: imageUrl == null ? null : NetworkImage(imageUrl),
      onBackgroundImageError: imageUrl == null ? null : (_, _) {},
      child: imageUrl == null
          ? Icon(
              Icons.person_rounded,
              size: size * .52,
              color: const Color(0xFF9A3D78),
            )
          : null,
    );
  }
}

class _ProfileLoadError extends StatelessWidget {
  const _ProfileLoadError({required this.onRetry});
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('用户主页加载失败'),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}
