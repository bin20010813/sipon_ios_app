import 'package:flutter/material.dart';

import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/shared/services/sipon_notification.dart';
import 'package:sipon/features/profile/data/user_profile_data.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'profile_edit_page.dart';
import 'notification_content_page.dart';

class ProfileNotificationsPage extends StatefulWidget {
  const ProfileNotificationsPage({super.key, this.profile, this.api});
  final UserProfileData? profile;
  final SiponApiService? api;

  @override
  State<ProfileNotificationsPage> createState() =>
      _ProfileNotificationsPageState();
}

class _ProfileNotificationsPageState extends State<ProfileNotificationsPage>
    with WidgetsBindingObserver {
  static const _pageSize = 20;
  late final SiponApiService _api = widget.api ?? SiponApiService();
  UserProfileData? _profile;
  List<SiponNotification> _notifications = const [];
  final Set<int> _marking = {};
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;
  bool _hasMore = false;
  bool _readingAll = false;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_busy || _readingAll || _marking.isNotEmpty) return;
    _busy = true;
    try {
      final raw = await _api.getMyProfile();
      if (mounted) _profile = UserProfileData.fromJson(raw);
    } on Exception {
      /* Messages remain available if profile loading fails. */
    }
    if (mounted) await _load(replace: true);
  }

  Future<void> _load({bool replace = false}) async {
    if (!replace && (_busy || !_hasMore || _readingAll)) return;
    setState(() => _busy = true);
    try {
      final raw = await _api.getMyNotifications(
        page: SiponPage(limit: _pageSize, offset: replace ? 0 : _offset),
      );
      if (!mounted) return;
      final items = raw.map(SiponNotification.fromJson).toList();
      setState(() {
        final previous = replace ? <SiponNotification>[] : _notifications;
        final ids = previous.map((item) => item.id).whereType<int>().toSet();
        _notifications = [
          ...previous,
          ...items.where((item) => item.id == null || ids.add(item.id!)),
        ];
        _offset = (replace ? 0 : _offset) + raw.length;
        _hasMore = raw.length == _pageSize;
        _failed = false;
      });
    } on Exception {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
        });
      }
    }
  }

  void _error(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(SiponLanguageScope.textOf(context).t(message))),
  );

  Future<void> _readAll() async {
    if (_readingAll || _busy || _marking.isNotEmpty) return;
    setState(() => _readingAll = true);
    try {
      await _api.markAllNotificationsRead();
      if (mounted) {
        setState(
          () => _notifications = _notifications
              .map((item) => item.asRead())
              .toList(),
        );
      }
    } on Exception {
      if (mounted) _error('标记已读失败，请重试');
    } finally {
      if (mounted) setState(() => _readingAll = false);
    }
  }

  Future<void> _open(SiponNotification item) async {
    if (_readingAll || (item.id != null && _marking.contains(item.id))) return;
    if (item.isUnread) {
      setState(() => _marking.add(item.id!));
      try {
        await _api.markNotificationsRead({
          'notificationIds': [item.id!],
        });
        if (mounted) {
          setState(
            () => _notifications = _notifications
                .map((row) => row.id == item.id ? row.asRead() : row)
                .toList(),
          );
        }
      } on Exception {
        if (mounted) _error('标记已读失败，请重试');
      } finally {
        if (mounted) setState(() => _marking.remove(item.id));
      }
    }
    if (!mounted) return;
    if (item.checkInId != null || item.routeId != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => NotificationContentPage(
            notification: item,
            api: _api,
            viewerId: _profile?.id,
          ),
        ),
      );
    } else if (item.isProfileModeration && _profile != null) {
      await Navigator.of(context).push<UserProfileData>(
        MaterialPageRoute(builder: (_) => ProfileEditPage(profile: _profile!)),
      );
      if (mounted) await _refresh();
    }
  }

  IconData _icon(SiponNotification item) => switch (item.type) {
    'check_in_like' => Icons.favorite_outline_rounded,
    'check_in_comment' => Icons.chat_bubble_outline_rounded,
    _ =>
      item.isReview
          ? Icons.fact_check_outlined
          : Icons.notifications_none_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final scheme = Theme.of(context).colorScheme;
    final visible = _notifications
        .where((item) => item.belongsTo(_profile))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(text.t('消息')),
        actions: [
          TextButton(
            onPressed: _readingAll || _busy || _marking.isNotEmpty
                ? null
                : _readAll,
            child: Text(text.t(_readingAll ? '处理中' : '全部已读')),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            if (_profile?.profileModerationStatus != null)
              _ModerationCard(profile: _profile!),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_failed)
              ListTile(
                title: Text(text.t('部分消息加载失败')),
                trailing: TextButton(
                  onPressed: _busy ? null : _refresh,
                  child: Text(text.t('重试')),
                ),
              ),
            if (!_loading && !_failed && visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text(text.t('暂无消息'))),
              ),
            for (final item in visible)
              Card(
                color: item.isUnread
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerLow,
                child: ListTile(
                  onTap: _busy || _readingAll ? null : () => _open(item),
                  isThreeLine: true,
                  leading: Icon(_icon(item)),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      fontWeight: item.isUnread
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.body.isNotEmpty) Text(item.body),
                      if (item.contentVersion != null)
                        Text('${text.t('审核内容版本')}：${item.contentVersion}'),
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (item.createdAt != null)
                            _formatDate(item.createdAt!),
                          text.t(item.isUnread ? '未读' : '已读'),
                        ].join(' · '),
                      ),
                    ],
                  ),
                  trailing:
                      item.checkInId != null ||
                          item.routeId != null ||
                          item.isProfileModeration
                      ? const Icon(Icons.chevron_right_rounded)
                      : null,
                ),
              ),
            if (_hasMore)
              TextButton(
                onPressed: _busy || _readingAll ? null : () => _load(),
                child: Text(text.t(_busy ? '加载中' : '加载更多消息')),
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
