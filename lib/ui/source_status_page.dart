part of '../home_page.dart';

class _SourcesPage extends StatelessWidget {
  const _SourcesPage({
    required this.open,
    required this.checkedAt,
    required this.failedSources,
    this.sourceStatuses = const [],
  });
  final Future<void> Function(Uri) open;
  final DateTime? checkedAt;
  final List<String> failedSources;

  /// Sunucunun bildirdiği kaynak durumları (boşsa sunucu kapalı/okunamadı).
  final List<SourceStatus> sourceStatuses;

  SourceStatus? _serverStatus(String id) =>
      sourceStatuses.where((s) => s.id == id).firstOrNull ??
      (id == 'sbb'
          ? sourceStatuses.where((s) => s.id == 'kamuilan_sbb').firstOrNull
          : null);
  String? _serverNote(String id) => _serverStatus(id)?.note;
  String _serverLabel(String id) => switch (_serverStatus(id)?.state) {
    SourceState.ok => 'Listeye erişildi',
    SourceState.failed => 'Kaynak yenilenemedi',
    SourceState.blocked => 'Kaynağa erişim engellendi',
    SourceState.disabled => 'Kaynak kapalı',
    null => 'Kaynak henüz denetlenmedi',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Resmî kaynaklar')),
    body: ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.update_outlined),
          title: Text(
            sourceStatuses.isEmpty ? 'Son denetim' : 'Son başarılı eşitleme',
          ),
          subtitle: Text(
            checkedAt == null
                ? 'Bu oturumda henüz denetlenmedi'
                : '${checkedAt!.day}.${checkedAt!.month}.${checkedAt!.year} '
                      '${checkedAt!.hour.toString().padLeft(2, '0')}:${checkedAt!.minute.toString().padLeft(2, '0')}',
          ),
        ),
        for (final (name, id, description) in [
          (
            'Kariyer Kapısı',
            'kariyerkapisi',
            'Resmî liste ve ilan metinleri sunucuda okunur; ayrıntılar cihazda saklanır.',
          ),
          (
            'Kamu İlanları (SBB)',
            'sbb',
            'Güncel yıl listesi; asıl ilan resmî PDF belgedir.',
          ),
          (
            'ilan.gov.tr',
            kIlanGovSourceId,
            'Personel alımı ilanları (belediye, üniversite, Resmî Gazete) '
                'sunucuda resmî portaldan okunur.',
          ),
          (
            'İŞKUR',
            kIskurSourceId,
            'Yalnız kamu işçi alımları (belediye vb.); özel sektör ilanları '
                'alınmaz.',
          ),
        ])
          ListTile(
            leading: Icon(
              _serverStatus(id) != null
                  ? _serverStatus(id)!.state == SourceState.ok
                        ? Icons.check_circle_outline
                        : Icons.error_outline
                  : Icons.help_outline,
            ),
            title: Text(name),
            subtitle: Text(
              _serverStatus(id) != null
                  ? '${_serverLabel(id)}. ${_serverNote(id) ?? description}'
                  : checkedAt != null && failedSources.contains(name)
                  ? 'Son denetim başarısız; önbellek korunuyor. $description'
                  : 'Kaynak henüz denetlenmedi. $description',
            ),
          ),
        const ListTile(
          leading: Icon(Icons.location_city_outlined),
          title: Text('Belediyeler'),
          subtitle: Text(
            'Belediye personel ilanları ilan.gov.tr (Basın İlan Kurumu) ve '
            'İŞKUR kamu ilanlarıyla gelir; "Belediye" süzgeciyle bulunur. '
            'İlanını yalnız kendi sitesinde yayımlayan belediyeler şimdilik '
            'kapsam dışıdır.',
          ),
        ),
      ],
    ),
  );
}
