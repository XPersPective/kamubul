import 'dart:io' show Platform;

/// Mağazaya bağlı özellikler. Android'de her zaman açıktır. iOS'ta reklam,
/// gerçek AdMob iOS kimlikleri derlemeye verildiğinde; Pro, App Store'da
/// abonelik ürünü satışa hazır olduğunda (IOS_PRO=true) açılır. Test
/// kimlikleriyle ya da satılamayan bir ürünle mağazaya çıkılmaz.
bool get adsAvailable =>
    !Platform.isIOS || const bool.hasEnvironment('ADMOB_APP_ID_IOS');

bool get proAvailable =>
    !Platform.isIOS || const bool.fromEnvironment('IOS_PRO');
