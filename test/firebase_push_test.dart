import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/notifications/firebase_push.dart';
import 'package:kamubul_core/kamubul_core.dart';

void main() {
  test('foreground FCM başlık, detay bağlantısı ve özet türünü korur', () {
    final notification = foregroundNotification(
      const RemoteMessage(
        notification: RemoteNotification(title: ' Yeni ilan ', body: 'Kurum'),
        data: {
          'url': 'https://kariyerkapisi.gov.tr/ilan',
          'kind': 'digest',
          'listingId': 'kariyer:opaque/with?#ü',
          'revision': '7',
          'eventId': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        },
      ),
    );
    expect(notification?.title, 'Yeni ilan');
    expect(notification?.body, 'Kurum');
    expect(notification?.listingUrl, 'https://kariyerkapisi.gov.tr/ilan');
    expect(notification?.digest, isTrue);
    expect(notification?.listingId, 'kariyer:opaque/with?#ü');
    expect(notification?.listingRevision, 7);
    expect(
      decodeAlertTap(notification?.tapPayload)?.listingId,
      notification?.listingId,
    );
    expect(notification?.eventId, 'a' * 64);
    expect(notification?.presentationId, 0x2aaaaaaa);
  });
  test('background and cold FCM tap share strict stable target decoding', () {
    final target = notificationTapPayload(
      const RemoteMessage(
        data: {
          'url': 'https://kariyerkapisi.gov.tr/ilan',
          'listingId': 'kariyer:one',
        },
      ),
    );
    expect(decodeAlertTap(target), (
      url: 'https://kariyerkapisi.gov.tr/ilan',
      listingId: 'kariyer:one',
      revision: null,
    ));
    for (final id in ['', 'x' * 201, 1]) {
      expect(
        notificationTapPayload(
          RemoteMessage(
            data: {'url': 'https://example.com/ilan', 'listingId': id},
          ),
        ),
        isNull,
      );
    }
    expect(
      notificationTapPayload(
        const RemoteMessage(data: {'url': 'https://example.com/ilan'}),
      ),
      'https://example.com/ilan',
    );
    for (final revision in ['0', '-1', 'bad', '9007199254740992', 2]) {
      expect(
        notificationTapPayload(
          RemoteMessage(
            data: {
              'url': 'https://example.com/ilan',
              'listingId': 'one',
              'revision': revision,
            },
          ),
        ),
        isNull,
      );
    }
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
