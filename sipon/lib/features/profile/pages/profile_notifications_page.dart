import 'package:flutter/material.dart';

import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/shared/services/sipon_notification.dart';
import 'package:sipon/features/profile/data/user_profile_data.dart';
import 'package:sipon/shared/localization/language_transform.dart';

class ProfileNotificationsPage extends StatefulWidget {
  const ProfileNotificationsPage({super.key, this.profile, this.api});

  final UserProfileData? profile;
  final SiponApiService? api;

  @override
  State<ProfileNotificationsPage> createState() =>
      _ProfileNotificationsPageState();
}

class _ProfileNotificationsPageState extends State<ProfileNotificationsPage> {
  late final SiponApiService _api = widget.api ?? SiponApiService();
  UserProfileData? _profile;
  List<SiponNotification> _notifications = const [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _refresh();
  }

  Future<void> _refresh() async {
    UserProfileData? profile = _profile;
    List<SiponNotification>? notifications;
    var failed = false;
    try {
      profile = UserProfileData.fromJson(await _api.getMyProfile());
    } on Exception {
      failed = profile == null;
    }
    try {
      notifications = (await _api.getMyNotifications())
          .map(SiponNotification.fromJson)
          .toList();
    } on Exception {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      if (notifications != null) _notifications = notifications;
      _failed = failed;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final scheme = Theme.of(context).colorScheme;
    final visible = _notifications
        .where((item) => item.belongsTo(_profile))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(text.t('消息'), style: TextStyle(color: scheme.onSurface)),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            if (_profile?.profileModerationStatus != null)
              _ModerationCard(profile: _profile!),
            if (_profile?.profileModerationStatus != null)
              const SizedBox(height: 20),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_failed)
              ListTile(
                title: Text(text.t('部分消息加载失败')),
                trailing: TextButton(
                  onPressed: _refresh,
                  child: Text(text.t('重试')),
                ),
              ),
            for (final notification in visible)
              _MessageBubble(
                timestamp: notification.createdAt,
                icon: notification.isProfileModeration
                    ? Icons.verified_user_outlined
                    : Icons.chat_bubble_outline_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        notification.body,
                        style: TextStyle(color: scheme.onSurface),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.child,
    required this.icon,
    this.timestamp,
  });

  final Widget child;
  final IconData icon;
  final DateTime? timestamp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = SiponLanguageScope.textOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          if (timestamp != null) ...[
            Text(
              _formatDate(timestamp!),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text.t('系统通知'),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                        ),
                      ),
                      child: child,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModerationCard extends StatelessWidget {
  const _ModerationCard({required this.profile});

  final UserProfileData profile;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final scheme = Theme.of(context).colorScheme;
    final status = profile.profileModerationStatus;
    final title = switch (status) {
      'pending' => '资料审核中',
      'approved' => '资料审核已通过',
      'rejected' => '资料审核未通过',
      _ => '资料审核状态',
    };
    final icon = switch (status) {
      'pending' => Icons.hourglass_top_rounded,
      'approved' => Icons.check_circle_outline_rounded,
      'rejected' => Icons.error_outline_rounded,
      _ => Icons.info_outline_rounded,
    };
    return _MessageBubble(
      icon: icon,
      timestamp: status == 'pending' ? null : profile.profileModeratedAt,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.t(title),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: scheme.onSurface,
                  ),
                ),
                if (status == 'pending') ...[
                  const SizedBox(height: 6),
                  Text(
                    text.t('昵称、头像或简介的修改正在审核中。'),
                    style: TextStyle(color: scheme.onSurface),
                  ),
                ],
                if (status == 'rejected' &&
                    profile.profileModerationReason != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${text.t('原因')}：${profile.profileModerationReason}',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
