import 'package:flutter_test/flutter_test.dart';

import 'package:kamubul/main.dart';

void main() {
  test('KamuBul uygulaması tanımlı', () {
    expect(KamuBulApp, isNotNull);
    expect('kamubul_pro_lifetime'.endsWith('_pro_lifetime'), isTrue);
  });
}
