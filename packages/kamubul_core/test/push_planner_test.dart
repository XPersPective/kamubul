import 'package:kamubul_core/kamubul_core.dart';
import 'package:test/test.dart';

DeviceRegistration _device({
  List<SubscribedSearch>? searches,
  int maxInstant = 3,
  int quietStart = 22,
  int quietEnd = 8,
}) => DeviceRegistration(
  fcmToken: 'x' * 30,
  platform: 'android',
  utcOffsetMinutes: 180,
  quietStartHour: quietStart,
  quietEndHour: quietEnd,
  maxInstantPerDay: maxInstant,
  searches:
      searches ??
      const [
        SubscribedSearch(id: 'a', name: 'Ankara', filters: {'sehir': 'ANKARA'}),
      ],
);

ListingRecord _listing(int n, {String place = 'ANKARA'}) => ListingRecord(
  url: 'https://x.gov.tr/$n',
  sourceId: 'kariyerkapisi',
  title: 'KURUM $n - İlan',
  category: 'Personel',
  publishedAt: DateTime(2026, 9, 28),
  fetchedAt: DateTime(2026, 9, 29, 9),
  places: [place],
);

final _day = DateTime(2026, 9, 29, 13); // öğlen: sessiz saat değil

void main() {
  test('eşleşen yeni ilan anlık bildirim üretir, eşleşmeyen üretmez', () {
    final plan = planDevicePush(
      device: _device(),
      newListings: [
        _listing(1),
        _listing(2, place: 'İZMİR'),
      ],
      state: const DevicePushState(),
      nowWall: _day,
    );
    expect(plan.toSend.map((n) => n.listingUrl), ['https://x.gov.tr/1']);
    expect(plan.state.instantSentToday, 1);
    expect(plan.state.sentDay, '2026-09-29');
  });

  test('günlük tavan aşılınca fazlası kuyruğa girer, ertesi gün boşalır', () {
    final plan = planDevicePush(
      device: _device(maxInstant: 2),
      newListings: [for (var i = 1; i <= 4; i++) _listing(i)],
      state: const DevicePushState(),
      nowWall: _day,
    );
    expect(plan.toSend, hasLength(2));
    expect(plan.state.queue.map((n) => n.listingUrl), [
      'https://x.gov.tr/3',
      'https://x.gov.tr/4',
    ]);

    final next = planDevicePush(
      device: _device(maxInstant: 2),
      newListings: const [],
      state: plan.state,
      nowWall: DateTime(2026, 9, 30, 9),
    );
    expect(next.toSend.map((n) => n.listingUrl), [
      'https://x.gov.tr/3',
      'https://x.gov.tr/4',
    ]);
    expect(next.state.queue, isEmpty);
    expect(next.state.sentDay, '2026-09-30');
  });

  test('sessiz saatte gönderilmez, kuyruğa alınır ve sabah gönderilir', () {
    final night = planDevicePush(
      device: _device(),
      newListings: [_listing(1)],
      state: const DevicePushState(),
      nowWall: DateTime(2026, 9, 29, 23, 30),
    );
    expect(night.toSend, isEmpty);
    expect(night.state.queue, hasLength(1));

    final morning = planDevicePush(
      device: _device(),
      newListings: const [],
      state: night.state,
      nowWall: DateTime(2026, 9, 30, 9),
    );
    expect(morning.toSend, hasLength(1));
    expect(morning.state.queue, isEmpty);
  });

  test('özet modu günde bir kez tek toplu bildirim üretir', () {
    final device = _device(
      searches: const [
        SubscribedSearch(
          id: 'd',
          name: 'Özet',
          filters: {'sehir': 'ANKARA', 'bildirim': 'digest'},
        ),
      ],
    );
    final first = planDevicePush(
      device: device,
      newListings: [_listing(1), _listing(2), _listing(3)],
      state: const DevicePushState(),
      nowWall: _day,
    );
    expect(first.toSend, hasLength(1));
    expect(first.toSend.single.digest, isTrue);
    expect(first.toSend.single.title, contains('3 yeni ilan'));
    expect(first.state.instantSentToday, 0); // özet, anlık tavana sayılmaz

    final second = planDevicePush(
      device: device,
      newListings: [_listing(4)],
      state: first.state,
      nowWall: DateTime(2026, 9, 29, 18),
    );
    expect(second.toSend, isEmpty);
  });

  test('kapalı mod ve yeni ilan yokken bildirim yok', () {
    final off = planDevicePush(
      device: _device(
        searches: const [
          SubscribedSearch(
            id: 'o',
            name: 'Kapalı',
            filters: {'sehir': 'ANKARA', 'bildirim': 'off'},
          ),
        ],
      ),
      newListings: [_listing(1)],
      state: const DevicePushState(),
      nowWall: _day,
    );
    expect(off.toSend, isEmpty);
    final none = planDevicePush(
      device: _device(),
      newListings: const [],
      state: const DevicePushState(),
      nowWall: _day,
    );
    expect(none.toSend, isEmpty);
  });

  test('durum JSON gidiş-dönüş ve bozuk durum boş okunur', () {
    final plan = planDevicePush(
      device: _device(maxInstant: 1),
      newListings: [_listing(1), _listing(2)],
      state: const DevicePushState(),
      nowWall: _day,
    );
    final restored = DevicePushState.fromJson(plan.state.toJson());
    expect(restored.queue.single.listingUrl, 'https://x.gov.tr/2');
    expect(restored.instantSentToday, 1);
    expect(DevicePushState.fromJson('bozuk').queue, isEmpty);
    expect(
      DevicePushState.fromJson({'queue': 5, 'instantSentToday': -3})
          .instantSentToday,
      0,
    );
  });
}
