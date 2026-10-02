/// T.C. İçişleri Bakanlığı valilik listesine göre 81 il:
/// https://www.icisleri.gov.tr/valilikler
const turkishCities = [
  'Adana',
  'Adıyaman',
  'Afyonkarahisar',
  'Ağrı',
  'Aksaray',
  'Amasya',
  'Ankara',
  'Antalya',
  'Ardahan',
  'Artvin',
  'Aydın',
  'Balıkesir',
  'Bartın',
  'Batman',
  'Bayburt',
  'Bilecik',
  'Bingöl',
  'Bitlis',
  'Bolu',
  'Burdur',
  'Bursa',
  'Çanakkale',
  'Çankırı',
  'Çorum',
  'Denizli',
  'Diyarbakır',
  'Düzce',
  'Edirne',
  'Elazığ',
  'Erzincan',
  'Erzurum',
  'Eskişehir',
  'Gaziantep',
  'Giresun',
  'Gümüşhane',
  'Hakkari',
  'Hatay',
  'Iğdır',
  'Isparta',
  'İstanbul',
  'İzmir',
  'Kahramanmaraş',
  'Karabük',
  'Karaman',
  'Kars',
  'Kastamonu',
  'Kayseri',
  'Kilis',
  'Kırıkkale',
  'Kırklareli',
  'Kırşehir',
  'Kocaeli',
  'Konya',
  'Kütahya',
  'Malatya',
  'Manisa',
  'Mardin',
  'Mersin',
  'Muğla',
  'Muş',
  'Nevşehir',
  'Niğde',
  'Ordu',
  'Osmaniye',
  'Rize',
  'Sakarya',
  'Samsun',
  'Siirt',
  'Sinop',
  'Sivas',
  'Şanlıurfa',
  'Şırnak',
  'Tekirdağ',
  'Tokat',
  'Trabzon',
  'Tunceli',
  'Uşak',
  'Van',
  'Yalova',
  'Yozgat',
  'Zonguldak',
];

String foldTurkish(String value) => value
    .trim()
    .toUpperCase()
    .replaceAll('İ', 'I')
    .replaceAll('Ç', 'C')
    .replaceAll('Ğ', 'G')
    .replaceAll('Ö', 'O')
    .replaceAll('Ş', 'S')
    .replaceAll('Ü', 'U');

String? canonicalCity(String value) {
  final folded = foldTurkish(value)
      .replaceAll('Â', 'A')
      .replaceAll('Î', 'I')
      .replaceAll('Û', 'U')
      .replaceFirst(RegExp(r'^CITY:'), '');
  for (final city in turkishCities) {
    if (foldTurkish(city) == folded) return city;
  }
  return null;
}

String cityLabel(String value) => value.trim().toUpperCase().startsWith('CITY:')
    ? canonicalCity(value) ?? value
    : value;
