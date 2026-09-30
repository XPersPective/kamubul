/// Bellek içi sabit pencere sayacı: yazma uçlarını istemci başına sınırlar.
/// Tek süreç içindir; ölçek büyürse Cloud Armor/Firebase Hosting önüne
/// taşınır. Süresi dolan girdiler temizlenir, bellek büyümez.
library;

class RateLimiter {
  RateLimiter({
    required this.maxPerWindow,
    this.window = const Duration(hours: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxPerWindow;
  final Duration window;
  final DateTime Function() _clock;
  final Map<String, (DateTime, int)> _hits = {};

  /// İstek kabul edilirse `true`.
  bool allow(String key) {
    final now = _clock();
    if (_hits.length > 10000) {
      _hits.removeWhere((_, hit) => now.difference(hit.$1) >= window);
    }
    final hit = _hits[key];
    if (hit == null || now.difference(hit.$1) >= window) {
      _hits[key] = (now, 1);
      return true;
    }
    if (hit.$2 >= maxPerWindow) return false;
    _hits[key] = (hit.$1, hit.$2 + 1);
    return true;
  }
}
