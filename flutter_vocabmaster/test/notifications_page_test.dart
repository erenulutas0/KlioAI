import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocabmaster/screens/notifications_page.dart';
import 'package:vocabmaster/services/social_service.dart';

class FakeSocialService extends SocialService {
  FakeSocialService({this.notifications = const [], this.shouldThrow = false});

  final List<dynamic> notifications;
  final bool shouldThrow;

  @override
  Future<List<dynamic>> getNotifications() async {
    if (shouldThrow) {
      throw Exception('network');
    }
    return notifications;
  }

  @override
  Future<void> markNotificationAsRead(int notificationId) async {}
}

void main() {
  testWidgets('opened push shows received card when social list is empty',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsPage(
          openedFromPush: true,
          socialService: FakeSocialService(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Push bildirimi alındı'), findsOneWidget);
    expect(
      find.text(
          'Bu test push başarıyla açıldı. Sosyal bildirim listeniz şu an boş.'),
      findsOneWidget,
    );
    expect(find.text('Bildirimler yüklenemedi'), findsNothing);
  });

  testWidgets('normal notification load failure shows snackbar',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationsPage(
          socialService: FakeSocialService(shouldThrow: true),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Bildirimler yüklenemedi'), findsOneWidget);
  });
}
