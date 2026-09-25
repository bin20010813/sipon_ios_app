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
    final visible = _notifications
        .where((item) => item.belongsTo(_profile))
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFFFFAFC),
      appBar: AppBar(
        title: Text(text.t('消息')),
        backgroundColor: const Color(0xFFFFFAFC),
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
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
            if (visible.isEmpty && !_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text(text.t('暂无消息'))),
              ),
            for (final notification in visible)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                color: Colors.white,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (notification.body.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(notification.body),
                      ],
                      if (notification.createdAt != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _formatDate(notification.createdAt!),
                          style: const TextStyle(
                            color: Color(0xFF8E8790),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
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
    return Card(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF9A3D78)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.t(title),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  if (status == 'pending') ...[
                    const SizedBox(height: 6),
                    Text(text.t('昵称、头像或简介的修改正在审核中。')),
                  ],
                  if (status == 'rejected' &&
                      profile.profileModerationReason != null) ...[
                    const SizedBox(height: 6),
                    Text('${text.t('原因')}：${profile.profileModerationReason}'),
                  ],
                  if (status != 'pending' &&
                      profile.profileModeratedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _formatDate(profile.profileModeratedAt!),
                      style: const TextStyle(
                        color: Color(0xFF8E8790),
                        fontSize: 12,
                      ),
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

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
