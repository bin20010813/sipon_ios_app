import 'package:flutter/material.dart';

import 'package:sipon/features/reviews/pages/review_detail_page.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/shared/services/home_moments_repository.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/shared/services/sipon_notification.dart';
import 'package:sipon/shared/widgets/check_in_comments_sheet.dart';

/// Always fetch current content with the signed-in user's permissions.
class NotificationContentPage extends StatefulWidget {
  const NotificationContentPage({
    super.key,
    required this.notification,
    required this.api,
    this.viewerId,
  });

  final SiponNotification notification;
  final SiponApiService api;
  final int? viewerId;

  @override
  State<NotificationContentPage> createState() =>
      _NotificationContentPageState();
}

class _NotificationContentPageState extends State<NotificationContentPage> {
  late Future<dynamic> _content = _fetch();

  Future<dynamic> _fetch() => widget.notification.checkInId != null
      ? widget.api.getCheckIn(widget.notification.checkInId!)
      : widget.api.getDrinkingRoute(widget.notification.routeId!);

  Future<void> _comments() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => CheckInCommentsSheet(
      checkInId: widget.notification.checkInId!,
      api: widget.api,
      viewerId: widget.viewerId,
      // The message center requires a session; the API still enforces auth.
      ensureLogin: ({bool force = false}) async => !force,
    ),
  );

  String _status(Object? value) => switch (value) {
    'approved' => '审核已通过',
    'rejected' => '审核未通过',
    'pending' => '审核中',
    _ => '状态未知',
  };

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    return FutureBuilder<dynamic>(
      future: _content,
      builder: (context, snapshot) {
        final value = snapshot.data;
        if (value is Map) {
          final entry = value.cast<String, dynamic>();
          final notification = widget.notification;
          final reviewText = notification.type == 'check_in_comment_review'
              ? notification.body
              : notification.isReview
              ? '${notification.body}\n当前内容：${_status(entry['moderationStatus'])}'
                    '${notification.contentVersion != null && notification.contentVersion != entry['version'] ? '\n内容已修改，这条消息对应修改前的审核结果。' : ''}'
              : null;
          if (notification.checkInId != null) {
            final moment = HomeMoment.fromJson(entry);
            return ReviewDetailPage(
              entry: entry,
              venue: moment.venue,
              author: moment.author,
              apiService: widget.api,
              notice: reviewText,
              onCommentsPressed:
                  entry['visibility'] == 'public' &&
                      (entry['moderationStatus'] == 'approved' ||
                          !entry.containsKey('moderationStatus'))
                  ? _comments
                  : null,
            );
          }
          return Scaffold(
            appBar: AppBar(title: Text(text.t('分享路线'))),
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  entry['title']?.toString() ?? text.t('分享路线'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                Text(reviewText ?? notification.body),
                for (final stop
                    in (entry['stops'] is List
                        ? entry['stops'] as List
                        : const []))
                  if (stop is Map)
                    ListTile(
                      title: Text(
                        (stop['barName'] ?? stop['name'] ?? '路线站点').toString(),
                      ),
                    ),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(text.t('消息详情'))),
          body: Center(
            child: snapshot.hasError
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.notification.body),
                        const SizedBox(height: 16),
                        Text(text.t('内容暂不可用，可能已删除、下架或不再对你可见。')),
                        TextButton(
                          onPressed: () => setState(() => _content = _fetch()),
                          child: Text(text.t('重试')),
                        ),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}
