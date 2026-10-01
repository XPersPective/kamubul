/// Cihazın sunucuya bildirdiği anonim bildirim aboneliği.
///
/// Hesap yoktur: cihaz rastgele bir kimlik ve gizli anahtar üretir; sunucu
/// yalnızca gizli anahtarın özetini saklar. Kayıt yalnızca FCM jetonu,
/// bildirim tercihleri ve kayıtlı arama süzgeçlerini taşır; profil (yaş,
/// eğitim, KPSS) yalnızca süzgeç değeri olarak, kullanıcı etiketi kaydettiyse
/// gider. Sunucu her alanı doğrular; bilinmeyen süzgeç anahtarları atılır.
library;

import '../data/search_criteria.dart';

final RegExp _deviceIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _secretPattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _searchIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

bool isValidDeviceId(String value) => _deviceIdPattern.hasMatch(value);
bool isValidDeviceSecret(String value) => _secretPattern.hasMatch(value);

/// Sunucuya gönderilmesine izin verilen süzgeç anahtarları.
const Set<String> kSubscribableFilterKeys = {
  'q',
  'kategori',
  'son30',
  'sehir',
  'yas',
  'yasTarih',
  'egitim',
  'kpss',
  'kpssPuan',
  'bildirim',
};

const int kMaxSubscribedSearches = 20;

class RegistrationFormatException implements Exception {
  const RegistrationFormatException(this.message);
  final String message;
  @override
  String toString() => 'RegistrationFormatException: $message';
}

class SubscribedSearch {
  const SubscribedSearch({
    required this.id,
    required this.name,
    required this.filters,
    this.criteria,
  });

  final String id;
  final String name;
  final Map<String, String> filters;
  final SearchCriteria? criteria;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'filters': filters};
  Map<String, Object?> toV2Json() => {
    'id': id,
    'name': name,
    'criteria': (criteria ?? SearchCriteria.fromLegacy(filters)).values,
    'mode': filters['bildirim'] ?? 'instant',
  };
}

class DeviceRegistration {
  const DeviceRegistration({
    required this.fcmToken,
    required this.platform,
    required this.utcOffsetMinutes,
    required this.quietStartHour,
    required this.quietEndHour,
    required this.maxInstantPerDay,
    required this.searches,
  });

  final String fcmToken;
  final String platform;
  final int utcOffsetMinutes;
  final int quietStartHour;
  final int quietEndHour;
  final int maxInstantPerDay;
  final List<SubscribedSearch> searches;

  Map<String, Object?> toJson() => {
    'fcmToken': fcmToken,
    'platform': platform,
    'utcOffsetMinutes': utcOffsetMinutes,
    'quietStartHour': quietStartHour,
    'quietEndHour': quietEndHour,
    'maxInstantPerDay': maxInstantPerDay,
    'searches': [for (final search in searches) search.toJson()],
  };
  Map<String, Object?> toV2Json() => {
    'fcmToken': fcmToken,
    'platform': platform,
    'quietStartHour': quietStartHour,
    'quietEndHour': quietEndHour,
    'maxInstantPerDay': maxInstantPerDay,
    'searches': [for (final search in searches) search.toV2Json()],
  };

  /// Güvenilmeyen JSON'u doğrular; geçersizse [RegistrationFormatException].
  static DeviceRegistration parse(Object? raw) {
    if (raw is! Map) {
      throw const RegistrationFormatException('nesne bekleniyor');
    }
    final token = raw['fcmToken'];
    if (token is! String || token.length < 20 || token.length > 4096) {
      throw const RegistrationFormatException('fcmToken geçersiz');
    }
    final platform = raw['platform'];
    if (platform != 'android' && platform != 'ios') {
      throw const RegistrationFormatException('platform geçersiz');
    }
    final offset = _intIn(
      raw['utcOffsetMinutes'],
      -720,
      840,
      'utcOffsetMinutes',
    );
    final quietStart = _intIn(raw['quietStartHour'], 0, 23, 'quietStartHour');
    final quietEnd = _intIn(raw['quietEndHour'], 0, 23, 'quietEndHour');
    final maxInstant = _intIn(
      raw['maxInstantPerDay'],
      1,
      20,
      'maxInstantPerDay',
    );
    final rawSearches = raw['searches'];
    if (rawSearches is! List || rawSearches.length > kMaxSubscribedSearches) {
      throw const RegistrationFormatException('searches geçersiz');
    }
    final searches = <SubscribedSearch>[];
    final ids = <String>{};
    for (final item in rawSearches) {
      if (item is! Map) {
        throw const RegistrationFormatException('etiket geçersiz');
      }
      final id = item['id'];
      final name = item['name'];
      if (id is! String || !_searchIdPattern.hasMatch(id) || !ids.add(id)) {
        throw const RegistrationFormatException('etiket kimliği geçersiz');
      }
      if (name is! String || name.trim().isEmpty || name.length > 80) {
        throw const RegistrationFormatException('etiket adı geçersiz');
      }
      final filters = <String, String>{};
      final rawFilters = item['filters'];
      if (rawFilters is Map) {
        for (final entry in rawFilters.entries) {
          final key = entry.key;
          final value = entry.value;
          if (key is! String || !kSubscribableFilterKeys.contains(key)) {
            continue;
          }
          if (value is! String || value.length > 100) {
            throw const RegistrationFormatException('süzgeç değeri geçersiz');
          }
          filters[key] = value;
        }
      }
      searches.add(
        SubscribedSearch(id: id, name: name.trim(), filters: filters),
      );
    }
    return DeviceRegistration(
      fcmToken: token,
      platform: platform as String,
      utcOffsetMinutes: offset,
      quietStartHour: quietStart,
      quietEndHour: quietEnd,
      maxInstantPerDay: maxInstant,
      searches: searches,
    );
  }
}

int _intIn(Object? raw, int min, int max, String field) {
  if (raw is! int || raw < min || raw > max) {
    throw RegistrationFormatException('$field geçersiz');
  }
  return raw;
}
