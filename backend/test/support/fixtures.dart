import 'package:kamubul_backend/src/storage.dart';
import 'package:kamubul_core/kamubul_core.dart';

const deviceId = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
const deviceSecret =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

DeviceRegistration registration({
  List<SubscribedSearch>? searches,
  int maxInstant = 5,
  String token = 'tokentokentokentokentoken',
}) => DeviceRegistration(
  fcmToken: token,
  platform: 'android',
  utcOffsetMinutes: 180,
  quietStartHour: 22,
  quietEndHour: 8,
  maxInstantPerDay: maxInstant,
  searches:
      searches ??
      const [
        SubscribedSearch(
          id: 's1',
          name: 'Ankara',
          filters: {'sehir': 'ANKARA'},
        ),
      ],
);

DeviceRecord deviceRecord({
  String id = deviceId,
  DeviceRegistration? reg,
  DateTime? updatedAt,
  DevicePushState state = const DevicePushState(),
}) => DeviceRecord(
  id: id,
  secretHash: 'ab' * 32,
  registration: reg ?? registration(),
  state: state,
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: updatedAt ?? DateTime.utc(2026, 9, 29),
);

ListingRecord listing(
  String url, {
  String source = 'kariyerkapisi',
  String title = 'KURUM - İlan',
  List<String> places = const [],
  DateTime? published,
}) => ListingRecord(
  url: url,
  sourceId: source,
  title: title,
  category: 'Personel',
  publishedAt: published ?? DateTime(2026, 9, 28),
  fetchedAt: DateTime(2026, 9, 29, 8),
  deadline: DateTime(2026, 10, 12, 23, 59),
  places: places,
);
