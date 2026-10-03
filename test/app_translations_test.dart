import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup loads core and Pro Turkish copy together', () async {
    final translations = await loadAppTranslations();
    for (final key in [
      'paywall.oneTime',
      'paywall.priceLoading',
      'paywall.restore',
      'about.title',
    ]) {
      expect(translations.text('tr', key), isNot(key), reason: key);
    }
  });
}
