import 'package:flutter/material.dart';

import 'package:kamubul_core/kamubul_core.dart';

/// PB-008 onboarding: en fazla 4 adım, atlanabilir; profil ilk kayıtlı
/// aramayı doldurur (şehir, eğitim, yaş, KPSS türü).
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    required this.onCreate,
    required this.onDone,
  });

  /// İlanları bul: profil süzgeçleriyle ilk kayıtlı aramayı yaratır.
  final Future<void> Function(Map<String, String> filters) onCreate;

  final void Function() onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _cityController = TextEditingController();
  final _ageController = TextEditingController();
  final _kpssController = TextEditingController();
  String? _education;
  int _step = 0;
  bool _saving = false;

  @override
  void dispose() {
    _cityController.dispose();
    _ageController.dispose();
    _kpssController.dispose();
    super.dispose();
  }

  static const _titles = [
    'Resmî kamu ilanları, tek yerde',
    'Nerede iş arıyorsunuz?',
    'Sizin şartlarınız',
    'Hazırsınız',
  ];

  Future<void> _finish() async {
    if (_saving) return;
    final age = _ageController.text.trim();
    final city = _cityController.text.trim();
    final filters = <String, String>{
      'q': '',
      'kategori': '0',
      'son30': '0',
      'sehir': city.isEmpty ? '' : canonicalCity(city) ?? city,
      'egitim': ?_education,
      'yas': age,
      if (age.isNotEmpty) 'yasTarih': dayKey(wallClock(DateTime.now())),
      'kpss': ?(_kpssController.text.trim().isEmpty
          ? null
          : _kpssController.text.trim().toUpperCase()),
      'bildirim': 'instant',
    };
    filters.removeWhere((key, value) => value.isEmpty);
    try {
      if (city.isNotEmpty && canonicalCity(city) == null) {
        throw const FormatException('cities');
      }
      if (age.isNotEmpty && int.tryParse(age) == null) {
        throw const FormatException('age');
      }
      SearchCriteria.fromLegacy(filters);
    } on FormatException catch (error) {
      final message = switch (error.message) {
        'age' => 'Yaşınızı 16–80 arasında tam sayı olarak girin.',
        'kpssType' => 'KPSS puan türünü P3, P93 veya P94 biçiminde girin.',
        'cities' => 'Geçerli bir şehir adı girin veya alanı boş bırakın.',
        _ => 'Bilgilerinizi kontrol edin. Alanları boş bırakabilirsiniz.',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onCreate(filters);
      if (mounted) widget.onDone();
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bilgiler kaydedilemedi. Yeniden deneyebilir veya atlayabilirsiniz.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: [
              Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: i <= _step
                              ? scheme.primary
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: _saving ? null : widget.onDone,
                    child: const Text('Atla'),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Icon(
                Icons.account_balance_outlined,
                size: 56,
                color: scheme.primary,
                semanticLabel: 'KamuBul',
              ),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  _titles[_step],
                  semanticsLabel: 'Adım ${_step + 1} / 4: ${_titles[_step]}',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
              Text(_body(_step), style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 24),
              if (_step == 1)
                Autocomplete<String>(
                  initialValue: _cityController.value,
                  optionsBuilder: (value) => value.text.trim().isEmpty
                      ? const Iterable<String>.empty()
                      : turkishCities
                            .where(
                              (city) =>
                                  foldTurkish(city)
                                      .contains(foldTurkish(value.text)),
                            )
                            .take(20),
                  onSelected: (value) => _cityController.text = value,
                  fieldViewBuilder:
                      (context, controller, focusNode, onSubmit) => TextField(
                        enabled: !_saving,
                        controller: controller,
                        focusNode: focusNode,
                        onChanged: (value) => _cityController.text = value,
                        decoration: const InputDecoration(
                          labelText: 'Şehir (örn. Ankara)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                ),
              if (_step == 2) ...[
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _education,
                  decoration: const InputDecoration(
                    labelText: 'Eğitim düzeyi',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Lise', child: Text('Lise')),
                    DropdownMenuItem(
                      value: 'Ön lisans',
                      child: Text('Ön lisans'),
                    ),
                    DropdownMenuItem(value: 'Lisans', child: Text('Lisans')),
                    DropdownMenuItem(
                      value: 'Yüksek lisans',
                      child: Text('Yüksek lisans'),
                    ),
                    DropdownMenuItem(value: 'Doktora', child: Text('Doktora')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _education = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  enabled: !_saving,
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Yaşınız',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              if (_step == 3)
                TextField(
                  enabled: !_saving,
                  controller: _kpssController,
                  decoration: const InputDecoration(
                    labelText: 'KPSS puan türünüz',
                    helperText: 'Örn. P3, P93 veya P94 — isteğe bağlı',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 32),
              Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: _saving ? null : () => setState(() => _step--),
                      child: const Text('Geri'),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving
                          ? null
                          : () {
                              if (_step < 3) {
                                setState(() => _step++);
                              } else {
                                _finish();
                              }
                            },
                      child: Text(
                        _saving
                            ? 'Kaydediliyor…'
                            : _step == 3
                            ? 'İlanları bul'
                            : 'Devam',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const _PrivacyNote(),
            ],
          ),
        ),
      ),
    );
  }

  String _body(int step) => switch (step) {
    0 =>
      'Kariyer Kapısı ve Kamu İlanları (SBB) gibi resmî kaynaklardan güncel '
          'ilanları takip edin. Koşullar kaynakta bulunabiliyorsa gösterilir; '
          'erişim sorunları uygulamada belirtilir.',
    1 =>
      'Süzgeçleri şehrinize göre ayarlayalım. Şehri boş bırakabilir, sonra '
          'istediğiniz zaman değiştirebilirsiniz.',
    2 =>
      'Yaş ve eğitim bilgisi, ilanlardaki şartlarla uyumu göstermek için '
          'kullanılır; yalnızca bu cihazda tutulur.',
    3 =>
      'KPSS puan türünüzü girerseniz uyumlu ilanlar öne çıkar. Puanınızı ve '
          'diğer koşulları daha sonra düzenleyebilirsiniz. Bildirimleri ayrıca açabilirsiniz.',
    _ => '',
  };
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) => Text(
    'KamuBul hesap istemez. Profiliniz cihazınızda kalır; sunucu bildirimlerini '
    'açarsanız seçtiğiniz arama kriterleri eşleştirme için sunucuya gönderilir.',
    style: Theme.of(context).textTheme.bodySmall,
    textAlign: TextAlign.center,
  );
}
