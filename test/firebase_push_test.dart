import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/notifications/firebase_push.dart';

void main() {
  test('foreground FCM başlık, detay bağlantısı ve özet türünü korur', () {
    final notification = foregroundNotification(
      const RemoteMessage(
        notification: RemoteNotification(title: ' Yeni ilan ', body: 'Kurum'),
        data: {
          'url': 'https://kariyerkapisi.gov.tr/ilan',
          'kind': 'digest',
          'eventId': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        },
      ),
    );
    expect(notification?.title, 'Yeni ilan');
    expect(notification?.body, 'Kurum');
    expect(notification?.listingUrl, 'https://kariyerkapisi.gov.tr/ilan');
    expect(notification?.digest, isTrue);
    expect(notification?.eventId, 'a' * 64);
    expect(notification?.presentationId, 0x2aaaaaaa);
  });
  test('sessiz veri mesajı ve geçersiz bağlantı bildirim üretmez', () {
    expect(
      foregroundNotification(
        const RemoteMessage(data: {'url': 'https://kariyerkapisi.gov.tr/ilan'}),
      ),
      isNull,
    );
    for (final url in [
      'http://example.com',
      'javascript:alert(1)',
      'https:',
      'https://user:pass@example.com',
      '',
    ]) {
      expect(
        foregroundNotification(
          RemoteMessage(
            notification: const RemoteNotification(title: 'İlan'),
            data: {'url': url, 'eventId': 'a' * 64},
          ),
        ),
        isNull,
      );
    }
  });
}
