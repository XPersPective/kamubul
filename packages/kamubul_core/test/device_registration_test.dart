import 'package:kamubul_core/kamubul_core.dart';
import 'package:test/test.dart';

Map<String, Object?> _valid() => {
  'fcmToken': 'f' * 40,
  'platform': 'android',
  'utcOffsetMinutes': 180,
  'quietStartHour': 22,
  'quietEndHour': 8,
  'maxInstantPerDay': 5,
  'searches': [
    {
      'id': 'abc-1',
      'name': 'Ankara işçi',
      'filters': {'sehir': 'ANKARA', 'kategori': '1', 'gizli': 'x'},
    },
  ],
};

void main() {
  test('geçerli kayıt okunur, bilinmeyen süzgeç anahtarı atılır', () {
    final reg = DeviceRegistration.parse(_valid());
    expect(reg.searches.single.filters, {'sehir': 'ANKARA', 'kategori': '1'});
    final again = DeviceRegistration.parse(reg.toJson());
    expect(again.maxInstantPerDay, 5);
    expect(again.searches.single.id, 'abc-1');
  });

  test('sınır dışı ve bozuk alanlar reddedilir', () {
    void bad(Map<String, Object?> Function(Map<String, Object?>) mutate) {
      expect(
        () => DeviceRegistration.parse(mutate(_valid())),
        throwsA(isA<RegistrationFormatException>()),
      );
    }

    bad((m) => {...m, 'fcmToken': 'kısa'});
    bad((m) => {...m, 'platform': 'windows'});
    bad((m) => {...m, 'utcOffsetMinutes': 9999});
    bad((m) => {...m, 'quietStartHour': 24});
    bad((m) => {...m, 'maxInstantPerDay': 0});
    bad((m) => {...m, 'searches': 'yok'});
    bad(
      (m) => {
        ...m,
        'searches': [
          {'id': 'a b', 'name': 'x', 'filters': <String, String>{}},
        ],
      },
    );
    bad(
      (m) => {
        ...m,
        'searches': [
          {
            'id': 'a',
            'name': 'x',
            'filters': {'q': 'y' * 101},
          },
        ],
      },
    );
    bad(
      (m) => {
        ...m,
        'searches': [
          for (var i = 0; i < 21; i++)
            {'id': 'k$i', 'name': 'x', 'filters': <String, String>{}},
        ],
      },
    );
    bad(
      (m) => {
        ...m,
        'searches': [
          {'id': 'a', 'name': 'x', 'filters': <String, String>{}},
          {'id': 'a', 'name': 'y', 'filters': <String, String>{}},
        ],
      },
    );
    expect(
      () => DeviceRegistration.parse('metin'),
      throwsA(isA<RegistrationFormatException>()),
    );
  });

  test('cihaz kimliği ve gizli anahtar biçimi', () {
    expect(isValidDeviceId('a' * 32), isTrue);
    expect(isValidDeviceId('A' * 32), isFalse);
    expect(isValidDeviceId('a' * 31), isFalse);
    expect(isValidDeviceSecret('0' * 64), isTrue);
    expect(isValidDeviceSecret('0' * 63), isFalse);
  });
}
