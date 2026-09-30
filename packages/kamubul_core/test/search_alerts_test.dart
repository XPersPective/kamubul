import 'package:test/test.dart';
import 'package:kamubul_core/data/listing_models.dart';
import 'package:kamubul_core/data/search_alerts.dart';

void main() {
  ListingRecord record(
    String url, {
    String title = 'İlan',
    String category = 'Sözleşmeli Personel',
    DateTime? publishedAt,
    int? maxAge,
    String? education,
    String? kpss,
    DateTime? deadline,
    bool saved = false,
  }) => ListingRecord(
    url: url,
    sourceId: 'kariyerkapisi',
    title: title,
    category: category,
    publishedAt: publishedAt ?? DateTime(2026, 9, 20),
    fetchedAt: DateTime(2026, 9, 27),
    maxAge: maxAge,
    education: education,
    kpss: kpss,
    deadline: deadline,
    saved: saved,
  );

  SavedSearch savedSearch(
    Map<String, String> filters, {
    String name = 'Test arama',
  }) => SavedSearch(
    id: 1,
    name: name,
    filters: filters,
    createdAt: DateTime(2026, 9, 1),
  );

  AlertConfig config({int instantSentToday = 0, int? digestSentDay}) =>
      AlertConfig(
        now: DateTime(2026, 9, 27, 10),
        quietStartHour: 22,
        quietEndHour: 8,
        maxInstantPerDay: 3,
        instantSentToday: instantSentToday,
        digestSentDay: digestSentDay,
      );

  test('eşleştirici temel ve kanıtlı süzgeçleri uygular', () {
    final filters = {'kategori': '2', 'yas': '35', 'kpss': 'P3'};
    expect(
      matchesFilters(record('a', maxAge: 35, kpss: 'P3'), filters),
      isTrue,
    );
    // Bilinmeyen yaşlı ilan yaş süzgecinde gösterilmez.
    expect(matchesFilters(record('b'), filters), isFalse);
    expect(
      matchesFilters(record('c', maxAge: 35, kpss: 'P94'), filters),
      isFalse,
    );
    expect(matchesFilters(record('d', category: 'İşçi'), filters), isFalse);
  });

  test('kurum adındaki şehir, ilan yeri olarak kabul edilmez', () {
    final titled = record('a', title: 'Ankara Üniversitesi personel alımı');
    expect(matchesFilters(titled, {'sehir': 'Ankara'}), isFalse);
    final located = ListingRecord(
      url: 'b',
      sourceId: 'kariyerkapisi',
      title: 'Personel alımı',
      category: 'Personel',
      publishedAt: DateTime(2026, 9, 20),
      fetchedAt: DateTime(2026, 9, 27),
      places: const ['ANKARA'],
    );
    expect(matchesFilters(located, {'sehir': 'Ankara'}), isTrue);
    expect(placeMatchesCity('İSTANBUL / MERKEZ', 'Istanbul'), isTrue);
  });

  test('resmî SBB işçi ilanı işçi kategorisine girer', () {
    expect(
      matchesFilters(record('iscilik', category: 'İşçi'), {'kategori': '1'}),
      isTrue,
    );
    expect(matchesFilters(record('personel'), {'kategori': '1'}), isFalse);
  });

  test('ileri yayın tarihli ilan genel listede ve bildirimde bekler', () {
    final scheduled = record('gelecek', publishedAt: DateTime(2026, 10, 12));
    final today = DateTime(2026, 9, 28, 15);
    expect(matchesFilters(scheduled, const {}, now: today), isFalse);
    expect(
      matchesFilters(scheduled, const {}, now: today, forSaved: true),
      isTrue,
    );
    expect(
      matchesFilters(scheduled, const {}, now: DateTime(2026, 10, 12)),
      isTrue,
    );
    final decision = decideAlerts(
      search: savedSearch(const {}),
      listings: [scheduled],
      previouslySeen: {},
      config: config(),
    );
    expect(decision.notifications, isEmpty);
    expect(decision.seenUrls, isEmpty);
  });

  test('eğitim ve staj duyurusu iş listesine girmez; kayıt korunur', () {
    final training = record('egitim', category: 'Yurt Dışı Eğitim İlanları');
    expect(matchesFilters(training, const {}), isFalse);
    expect(matchesFilters(training, const {}, forSaved: true), isTrue);
  });

  test('anlık mod: yalnızca yeni ilanlar, günlük tavan', () {
    final search = savedSearch({'kategori': '2'});
    final listings = [
      record('yeni1'),
      record('yeni2'),
      record('yeni3'),
      record('yeni4'),
    ];
    final decision = decideAlerts(
      search: search,
      listings: listings,
      previouslySeen: {},
      config: config(),
    );
    expect(decision.notifications, hasLength(3));
    expect(decision.seenUrls, hasLength(4));
  });

  test('aynı ilan ikinci denetimde tekrar bildirilmez', () {
    final search = savedSearch({'kategori': '2'});
    final listings = [record('a'), record('b')];
    final first = decideAlerts(
      search: search,
      listings: listings,
      previouslySeen: {},
      config: config(),
    );
    final second = decideAlerts(
      search: search,
      listings: listings,
      previouslySeen: first.seenUrls,
      config: config(),
    );
    expect(second.notifications, isEmpty);
  });

  test('kapalı mod bildirim üretmez ama görüldü işaretler', () {
    final search = savedSearch({'kategori': '2', 'bildirim': 'off'});
    final decision = decideAlerts(
      search: search,
      listings: [record('a')],
      previouslySeen: {},
      config: config(),
    );
    expect(decision.notifications, isEmpty);
    expect(decision.seenUrls, contains('a'));
  });

  test('sessiz saatlerde anlık bildirim gönderilmez', () {
    final search = savedSearch({'kategori': '2'});
    final night = AlertConfig(
      now: DateTime(2026, 9, 27, 23, 30),
      quietStartHour: 22,
      quietEndHour: 8,
      maxInstantPerDay: 3,
      instantSentToday: 0,
      digestSentDay: null,
    );
    final decision = decideAlerts(
      search: search,
      listings: [record('a')],
      previouslySeen: {},
      config: night,
    );
    expect(decision.notifications, isEmpty);
    // Sessiz saatte bulunan ilan kaybolmaz; kuyruğa alınır.
    expect(decision.held, hasLength(1));
    expect(decision.held.single.listingUrl, 'a');
  });

  test('günlük tavan taşması ertelenir, ilk gelen önce gönderilir', () {
    final search = savedSearch({'kategori': '2'});
    final listings = [
      record('yeni1'),
      record('yeni2'),
      record('yeni3'),
      record('yeni4'),
    ];
    final decision = decideAlerts(
      search: search,
      listings: listings,
      previouslySeen: {},
      config: config(instantSentToday: 2),
    );
    // Tavan 3, bugün 2 gönderilmiş: 1 gider, 3 ertelenir.
    expect(decision.notifications, hasLength(1));
    expect(decision.held.map((item) => item.listingUrl), [
      'yeni2',
      'yeni3',
      'yeni4',
    ]);
  });

  test('özet sessiz saatte üretilir ama kuyruğa alınır', () {
    final search = savedSearch({'kategori': '2', 'bildirim': 'digest'});
    final night = AlertConfig(
      now: DateTime(2026, 9, 27, 23, 30),
      quietStartHour: 22,
      quietEndHour: 8,
      maxInstantPerDay: 3,
      instantSentToday: 0,
      digestSentDay: null,
    );
    final decision = decideAlerts(
      search: search,
      listings: [record('a'), record('b')],
      previouslySeen: {},
      config: night,
    );
    expect(decision.notifications, isEmpty);
    expect(decision.held, hasLength(1));
    expect(decision.held.single.title, contains('2 yeni ilan'));
  });

  test('özet mod günde bir kez, kuyrukla gönderilir', () {
    final search = savedSearch({'kategori': '2', 'bildirim': 'digest'});
    final listings = [record('a'), record('b')];
    final first = decideAlerts(
      search: search,
      listings: listings,
      previouslySeen: {},
      config: config(),
    );
    expect(first.notifications, hasLength(1));
    expect(first.notifications.single.title, contains('2 yeni ilan'));
    // Aynı gün ikinci denetim: yeni ilan yoksa özet tekrarlanmaz.
    final second = decideAlerts(
      search: search,
      listings: listings,
      previouslySeen: first.seenUrls,
      config: config(digestSentDay: 27),
    );
    expect(second.notifications, isEmpty);
  });

  test('son başvuru hatırlatıcısı kayıtlı ilanda bir kez çalışır', () {
    final soon = record(
      'hatirla',
      deadline: DateTime(2026, 9, 29),
      saved: true,
    );
    final reminder = deadlineReminder(
      record: soon,
      alreadyReminded: {},
      now: DateTime(2026, 9, 27),
    );
    expect(reminder, isNotNull);
    expect(reminder!.title, 'Son 2 gün');
    // Kaydedilmemiş ilan hatırlatılmaz.
    expect(
      deadlineReminder(
        record: record('kayitsiz', deadline: DateTime(2026, 9, 29)),
        alreadyReminded: {},
        now: DateTime(2026, 9, 27),
      ),
      isNull,
    );
    // Süresi geçmiş ilan hatırlatılmaz.
    expect(
      deadlineReminder(
        record: soon,
        alreadyReminded: {},
        now: DateTime(2026, 10, 1),
      ),
      isNull,
    );
  });

  test('son30 süzgeci yayın tarihindeki SBB satırına başvuru bitişinden bakar', () {
    // SBB satırı yayın tarihi vermez; yakınlık göstergesi başvuru penceresi
    // bitişidir. Hem tarihi bilinmeyen hem penceresi eski satır dışarıda kalır.
    ListingRecord sbbRecord(String url, {DateTime? deadline}) => ListingRecord(
      url: url,
      sourceId: 'kamuilan_sbb',
      title: 'Kurum — Personel Alımı',
      category: 'Kamu Personeli',
      publishedAt: null,
      fetchedAt: DateTime(2026, 9, 27),
      deadline: deadline,
    );
    final now = DateTime(2026, 9, 27);
    final filters = {'son30': '1'};
    expect(
      matchesFilters(
        sbbRecord('acik', deadline: DateTime(2026, 10, 5)),
        filters,
        now: now,
      ),
      isTrue,
    );
    expect(
      matchesFilters(
        sbbRecord('yeni-kapandi', deadline: DateTime(2026, 9, 20)),
        filters,
        now: now,
      ),
      isTrue,
    );
    expect(
      matchesFilters(
        sbbRecord('eski', deadline: DateTime(2026, 8, 1)),
        filters,
        now: now,
      ),
      isFalse,
    );
    expect(matchesFilters(sbbRecord('belirsiz'), filters, now: now), isFalse);
  });
}
