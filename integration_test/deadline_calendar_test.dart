import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kamubul/data/listing_store.dart';
import 'package:kamubul/listings/official_listing_page.dart';
import 'package:kamubul/ui/premium.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native calendar rejects invalid dates and shows recovery on a device without a calendar',
    (tester) async {
      const channel = MethodChannel('kamubul/calendar');
      await expectLater(
        channel.invokeMethod<bool>('insert', {
          'year': 2027,
          'month': 2,
          'day': 30,
          'title': 'Invalid date',
          'description': '',
        }),
        throwsA(isA<PlatformException>()),
      );
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          theme: premiumTheme(ThemeData()),
          home: OfficialListingPage(
            now: now,
            listing: ListingRecord(
              url: 'https://www.ilan.gov.tr/ilan/123',
              sourceId: 'ilangov',
              title: 'Takvim kontrolü',
              category: 'Personel',
              publishedAt: now,
              fetchedAt: now,
              deadline: now.add(const Duration(days: 2)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Takvime ekle'));
      await tester.tap(find.text('Takvime ekle'));
      await tester.pumpAndSettle();
      // Bu integration fixture takvim uygulaması olmayan test cihazında çalışır.
      expect(find.textContaining('Bir takvim uygulaması'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('İlan ayrıntısı'), findsOneWidget);
    },
  );
}
