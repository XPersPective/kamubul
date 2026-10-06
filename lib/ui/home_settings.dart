part of '../home_page.dart';

/// Ayarlar sekmesi, Pro kartı ve sunucu bildirim açıklaması.
extension _HomeSettings on _KamuHomePageState {
  void _showServerPushInfo() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sunucudan anlık bildirim'),
      content: const SingleChildScrollView(
        child: Text(
          'Açtığınızda kurulum kimliğiniz, bildirim jetonunuz ve bildirimi açık '
          'aramalarınızın adları, kriterleri ve tercihleri Cloudflare '
          'sunucusuna gönderilir; yeni ilan bu kriterlere uyunca bildirim '
          'gelir. Sessiz saatler 22:00–08:00.\n\nKapatınca yalnız sunucudaki '
          'bu bildirim kaydı silinir. Cihazınızdaki aramalarınız, '
          'kriterleriniz ve kaydettiğiniz ilanlar SİLİNMEZ; uygulama '
          'kapansa ya da günler geçse de yerinde kalır. Ayrıntı için '
          'gizlilik politikasına bakın.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tamam'),
        ),
      ],
    ),
  );

  Widget _proCard() {
    final scheme = Theme.of(context).colorScheme;
    final trialDays = trialDaysLeft(widget.policy, DateTime.now());
    final isPro = widget.pro.isPro;
    final text = isPro
        ? 'Pro etkin. Teşekkürler; reklamlar kapalı.'
        : trialDays > 0
        ? '${trialDays == 1 ? 'Reklamsız deneme son gün. ' : 'Reklamsız deneme: $trialDays gün kaldı. '}'
              'Sonrasında küçük banner ve seyrek tam ekran reklamlar gelir; '
              'aylık Pro bunları kaldırır.'
        : 'Reklamsız deneyim ve Asistan’da günde 100 soru hakkı. '
              'Dilediğiniz zaman iptal edebilirsiniz.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Material(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(PremiumShape.barRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(PremiumShape.barRadius),
          onTap: _openPaywall,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  size: 34,
                  color: scheme.onPrimaryContainer,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KamuBul Pro',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text,
                        style: TextStyle(
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: 0.9,
                          ),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsView() => ListView(
    padding: const EdgeInsets.only(bottom: 24),
    children: [
      _proCard(),
      SettingsGroup(
        title: 'Görünüm ve üyelik',
        children: [
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Tema'),
            trailing: DropdownButton<ThemeMode>(
              value: widget.theme.mode,
              onChanged: (value) {
                if (value != null) widget.theme.setMode(value);
              },
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('Sistem'),
                ),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Açık')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Koyu')),
              ],
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Bildirimler',
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Bildirimler'),
            subtitle: const Text('Uygun ilanlar ve son başvuru hatırlatmaları'),
            onTap: () async {
              final granted = await requestAlertPermission(context);
              if (!mounted) return;
              if (granted) await runAlertCheckNow();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    granted
                        ? 'Bildirimler açık. Uygun yeni ilanlar ve son başvuru '
                              'hatırlatmaları gelecek.'
                        : 'Bildirim izni verilmedi; uygulama yine de çalışır.',
                  ),
                ),
              );
            },
          ),
          if (pushRegistrar != null)
            SwitchListTile(
              secondary: const Icon(Icons.cloud_outlined),
              title: const Text('Sunucudan anlık bildirim'),
              subtitle: Text.rich(
                TextSpan(
                  text: 'Uygulama kapalıyken de yeni ilan bildirimi. ',
                  children: [
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: InkWell(
                        onTap: _showServerPushInfo,
                        child: Text(
                          'Ayrıntılar',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              value: pushRegistrar!.enabled,
              onChanged: _setServerPush,
            ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Bildirim geçmişi'),
            subtitle: const Text('Gönderilen ve bekleyen uyarılar'),
            onTap: () => Navigator.of(context)
                .push(sharedAxisRoute<void>(const NotificationCenterPage())),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Kaynaklar',
        children: [
          if (_otherApps != null)
            ListTile(
              leading: const Icon(Icons.explore_outlined),
              title: const Text('Diğer uygulamalarımız'),
              subtitle: const Text('Uygulamalarımızı keşfedin.'),
              onTap: _openOtherApps,
            ),
          ListTile(
            leading: const Icon(Icons.source_outlined),
            title: const Text('Resmî kaynaklar'),
            onTap: () => Navigator.of(context).push(
              sharedAxisRoute<void>(
                _SourcesPage(
                  open: _open,
                  checkedAt: _remoteLastSuccess ?? _lastRefresh,
                  failedSources: _failedSources,
                  sourceStatuses: _sourceStatuses,
                ),
              ),
            ),
          ),
        ],
      ),
      SettingsGroup(
        title: 'Geri bildirim',
        children: [
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Uygulamayı paylaş'),
            onTap: _shareApp,
          ),
          ListTile(
            leading: const Icon(Icons.star_rate_outlined),
            title: const Text('Puan ver'),
            onTap: _openRatePage,
          ),
        ],
      ),
      SettingsGroup(
        title: 'Hakkında',
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Hakkında ve lisanslar'),
            onTap: () => Navigator.of(
              context,
            ).push(sharedAxisRoute<void>(AboutPage(identity: widget.identity))),
          ),
        ],
      ),
    ],
  );
}
