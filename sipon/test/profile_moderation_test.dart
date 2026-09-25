import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sipon/shared/localization/language_transform.dart';
import 'package:sipon/features/profile/pages/profile_notifications_page.dart';
import 'package:sipon/shared/services/sipon_api_service.dart';
import 'package:sipon/shared/services/sipon_notification.dart';
import 'package:sipon/features/profile/data/user_profile_data.dart';

class _NotificationsApi extends SiponApiService {
  @override
  Future<dynamic> getMyProfile() async => {
    'profileModerationStatus': 'rejected',
    'profileVersion': 2,
    'profileModerationReason': '请更换头像',
  };

  @override
  Future<List<dynamic>> getMyNotifications({
    SiponPage page = const SiponPage(),
  }) async => [
    {
      'type': 'PROFILE_MODERATION_REJECTED',
      'title': '旧资料结果',
      'profileVersion': 1,
    },
    {'type': 'SYSTEM', 'title': '其他消息'},
  ];
}

void main() {
  test('自己的资料解析审核字段，合并概览后仍保留', () {
    final profile = UserProfileData.fromJson({
      'id': 100000001,
      'profileModerationStatus': 'rejected',
      'profileVersion': 2,
      'profileModerationReason': '请更换头像',
      'profileModeratedAt': '2026-09-23T08:00:00Z',
    }).mergeOverview({'checkInCount': 3});

    expect(profile.profileModerationStatus, 'rejected');
    expect(profile.profileVersion, 2);
    expect(profile.profileModerationReason, '请更换头像');
    expect(profile.profileModeratedAt, DateTime.utc(2026, 9, 23, 8));
    expect(profile.checkInCount, 3);
  });

  test('旧版本和无版本的资料审核消息不显示', () {
    final profile = UserProfileData.fromJson({
      'profileModerationStatus': 'pending',
      'profileVersion': 2,
    });
    final old = SiponNotification.fromJson({
      'type': 'PROFILE_MODERATION_REJECTED',
      'payload': {'profileVersion': 1},
      'body': '旧版本被驳回',
    });
    final current = SiponNotification.fromJson({
      'type': 'PROFILE_MODERATION_PENDING',
      'data': {'profileVersion': 2},
    });
    final missingVersion = SiponNotification.fromJson({
      'type': 'PROFILE_MODERATION_APPROVED',
    });
    final other = SiponNotification.fromJson({'type': 'SYSTEM'});

    expect(old.belongsTo(profile), isFalse);
    expect(current.belongsTo(profile), isTrue);
    expect(missingVersion.belongsTo(profile), isFalse);
    expect(other.belongsTo(profile), isTrue);
  });

  testWidgets('铃铛页面展示当前驳回原因并隐藏旧版本消息', (tester) async {
    await tester.pumpWidget(
      SiponLanguageScope(
        controller: SiponLanguageController(),
        child: MaterialApp(
          home: ProfileNotificationsPage(api: _NotificationsApi()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('资料审核未通过'), findsOneWidget);
    expect(find.text('原因：请更换头像'), findsOneWidget);
    expect(find.text('旧资料结果'), findsNothing);
    expect(find.text('其他消息'), findsOneWidget);
  });
}
