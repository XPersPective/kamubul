import 'package:flutter/material.dart';

import '../notifications/alert_service.dart';

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

  static const _titles = [
    'Resmî kamu ilanları, tek yerde',
    'Nerede iş arıyorsunuz?',
    'Sizin şartlarınız',
    'Hazırsınız',
  ];

  Future<void> _finish() async {
    final filters = <String, String>{
      'q': '',
      'kategori': '0',
      'son30': '0',
      'sehir': _cityController.text.trim(),
      'egitim': ?_education,
      'yas': ?int.tryParse(_ageController.text.trim())?.toString(),
      'kpss': ?(_kpssController.text.trim().isEmpty
          ? null
          : _kpssController.text.trim().toUpperCase()),
      'bildirim': 'instant',
    };
    filters.removeWhere((key, value) => value.isEmpty);
    await widget.onCreate(filters);
    if (!mounted) return;
    await requestAlertPermission(context);
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  TextButton(onPressed: _finish, child: const Text('Atla')),
                ],
              ),
              const Spacer(),
              Icon(
                Icons.account_balance_outlined,
                size: 56,
                color: scheme.primary,
                semanticLabel: 'KamuBul',
              ),
              const SizedBox(height: 16),
              Text(
                _titles[_step],
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(_body(_step), style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 24),
              if (_step == 1)
                TextField(
                  controller: _cityController,
                  decoration: const InputDecoration(
                    labelText: 'Şehir (örn. Ankara)',
                    border: OutlineInputBorder(),
                  ),
                ),
              if (_step == 2) ...[
                DropdownButtonFormField<String>(
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
                  onChanged: (value) => setState(() => _education = value),
                ),
                const SizedBox(height: 12),
                TextField(
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
                  controller: _kpssController,
                  decoration: const InputDecoration(
                    labelText:
                        'KPSS puan türünüz (örn. P3, P93) — isteğe bağlı',
                    border: OutlineInputBorder(),
                  ),
                ),
              const Spacer(),
              Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: () => setState(() => _step--),
                      child: const Text('Geri'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      if (_step < 3) {
                        setState(() => _step++);
                      } else {
                        _finish();
                      }
                    },
                    child: Text(_step == 3 ? 'İlanları bul' : 'Devam'),
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
          'ilanlar; koşullar kaynak cümlesiyle gösterilir.',
    1 =>
      'Süzgeçleri şehrinize göre ayarlayalım. Şehri boş bırakabilir, sonra '
          'istediğiniz zaman değiştirebilirsiniz.',
    2 =>
      'Yaş ve eğitim bilgisi, ilanlardaki şartlarla uyumu göstermek için '
          'kullanılır; yalnızca bu cihazda tutulur.',
    3 =>
      'KPSS puan türünüzü girerseniz uyumlu ilanlar öne çıkar. Bitirince ilk '
          'kayıtlı aramanız hazır olacak.',
    _ => '',
  };
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) => Text(
    'KamuBul hesap istemez; tercihleriniz cihazınızda kalır.',
    style: Theme.of(context).textTheme.bodySmall,
    textAlign: TextAlign.center,
  );
}
