import 'package:flutter_test/flutter_test.dart';
import 'package:kamubul/ui/turkish.dart';

void main() {
  test('Türkçe liste dizimi bağlaçları', () {
    expect(turkishList(const []), '');
    expect(turkishList(const ['A']), 'A');
    expect(turkishList(const ['A', 'B']), 'A ve B');
    expect(turkishList(const ['A', 'B', 'C']), 'A, B ve C');
  });
}
