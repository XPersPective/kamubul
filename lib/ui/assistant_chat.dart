import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/assistant_client.dart';
import 'premium.dart';
import 'premium_widgets.dart';

/// Sohbette görüntülenen tek mesaj.
class ChatMessage {
  ChatMessage.user(this.text)
    : fromUser = true,
      criteria = null,
      upgrade = false;
  ChatMessage.assistant(this.text, {this.criteria, this.upgrade = false})
    : fromUser = false;

  final String text;
  final bool fromUser;
  final Map<String, Object?>? criteria;

  /// Ücretsiz hak doldu: mesajın altında "Pro'ya geç" gösterilir.
  final bool upgrade;
}

/// KamuBul Asistan: kamu ilanları için kapsamı sınırlı yapay zekâ sohbeti.
/// İlan seçiliyse yanıtlar o ilanın resmî metnine dayanır.
class AssistantChatView extends StatefulWidget {
  const AssistantChatView({
    super.key,
    required this.client,
    required this.messages,
    this.listingTitle,
    this.loadListingText,
    this.onClearListing,
    this.onOpenListing,
    this.criteriaSummary,
    this.onSaveCriteria,
    this.listingGuide,
    this.isPro = false,
    this.onUpgrade,
    this.onNewChat,
    this.profile,
  });

  final AssistantClient client;

  /// Sohbet geçmişi üst bileşende tutulur; sekme değişince kaybolmaz.
  final List<ChatMessage> messages;
  final String? listingTitle;
  final Future<String?> Function()? loadListingText;
  final VoidCallback? onClearListing;
  final VoidCallback? onOpenListing;
  final String Function(Map<String, Object?> criteria)? criteriaSummary;
  final Future<void> Function(Map<String, Object?> criteria)? onSaveCriteria;
  final Widget? listingGuide;
  final bool isPro;
  final VoidCallback? onUpgrade;

  /// Mesajları ve seçili ilanı temizleyip yeni sohbet başlatır.
  final VoidCallback? onNewChat;

  /// Kullanıcının kayıtlı kriterleri: "bana uygun mu?" için salt okunur bağlam.
  final Map<String, Object?>? profile;

  @override
  State<AssistantChatView> createState() => _AssistantChatViewState();
}

class _AssistantChatViewState extends State<AssistantChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _busy = false;
  String? _listingText;
  String? _loadedFor;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<String> get _suggestions => widget.listingTitle != null
      ? const [
          'Bu ilan bana uygun mu?',
          'Bu ilanın başvuru şartları neler?',
          'Yaş sınırı var mı?',
          'Hangi belgeler gerekiyor?',
          'Son başvuru tarihi ne zaman?',
        ]
      : const [
          'Ankara\'da lisans mezunu, 28 yaşında, KPSS P3 75 bilişim ilanları',
          'KPSS P3 ve P93 puan türleri ne demek?',
          'Sözleşmeli ve kadrolu personel farkı nedir?',
        ];

  Future<String?> _contextText() async {
    final title = widget.listingTitle;
    if (title == null || widget.loadListingText == null) return null;
    if (_loadedFor == title) return _listingText;
    try {
      _listingText = await widget.loadListingText!();
    } on Object {
      _listingText = null;
    }
    _loadedFor = title;
    return _listingText;
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (_busy || text.length < 2) return;
    HapticFeedback.selectionClick();
    final history = [
      for (final m in widget.messages)
        (role: m.fromUser ? 'user' : 'assistant', text: m.text),
    ];
    setState(() {
      widget.messages.add(ChatMessage.user(text));
      _busy = true;
      _input.clear();
    });
    _scrollToEnd();
    try {
      final listingText = await _contextText();
      final reply = await widget.client.chat(
        text,
        history: history,
        listingTitle: widget.listingTitle,
        listingText: listingText,
        pro: widget.isPro,
        profile: widget.profile,
      );
      widget.messages.add(
        ChatMessage.assistant(reply.reply, criteria: reply.criteria),
      );
    } on AssistantException catch (error) {
      widget.messages.add(
        ChatMessage.assistant(error.message, upgrade: error.upgrade),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: PremiumMotion.settleDuration,
          curve: PremiumMotion.settleCurve,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            children: [
              const HeroPanel(
                eyebrow: 'YAPAY ZEKÂ DESTEKLİ',
                title: 'KamuBul Asistan',
                subtitle:
                    'Kamu ilanları, başvuru şartları ve arama kriterleriniz '
                    'için sorun. Konu dışı sorulara yanıt vermez.',
              ),
              const SizedBox(height: 12),
              if (widget.onNewChat != null &&
                  (widget.messages.isNotEmpty || widget.listingTitle != null))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _busy ? null : widget.onNewChat,
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('Yeni sohbet'),
                  ),
                ),
              if (widget.listingTitle != null) _listingCard(scheme),
              if (widget.listingGuide != null)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: widget.listingGuide!,
                  ),
                ),
              if (widget.messages.isEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Örnek sorular',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _suggestions)
                      ActionChip(
                        avatar: const Icon(Icons.bolt_rounded, size: 18),
                        label: Text(s),
                        onPressed: _busy ? null : () => _send(s),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              for (final m in widget.messages) _bubble(m, scheme),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Asistan yanıtlıyor…',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Yanıtlar yapay zekâ ile üretilir; başvurmadan önce resmî '
                  'ilanı kontrol edin. Kişisel bilgi yazmayın. Günlük kullanım '
                  'sınırlıdır.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        _composer(scheme),
      ],
    );
  }

  Widget _listingCard(ColorScheme scheme) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Row(
        children: [
          InstitutionAvatar(title: widget.listingTitle!, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SEÇİLİ İLAN',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.listingTitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (widget.onOpenListing != null)
            IconButton(
              tooltip: 'İlanı aç',
              onPressed: widget.onOpenListing,
              icon: const Icon(Icons.article_outlined),
            ),
          if (widget.onClearListing != null)
            IconButton(
              tooltip: 'Seçimi kaldır',
              onPressed: widget.onClearListing,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    ),
  );

  Widget _bubble(ChatMessage m, ColorScheme scheme) {
    final criteria = m.criteria;
    return Align(
      alignment: m.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.84,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: m.fromUser ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(m.fromUser ? 18 : 4),
              bottomRight: Radius.circular(m.fromUser ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                // Model bazen Markdown kalın (**) kullanır; düz metinde gösterilmez.
                m.text.replaceAll('**', ''),
                style: TextStyle(
                  color: m.fromUser ? scheme.onPrimary : scheme.onSurface,
                  height: 1.45,
                ),
              ),
              if (m.upgrade && !widget.isPro && widget.onUpgrade != null) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: widget.onUpgrade,
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: const Text('Pro\'ya geç'),
                ),
              ],
              if (criteria != null && widget.onSaveCriteria != null) ...[
                if (widget.criteriaSummary != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.criteriaSummary!(criteria),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () => widget.onSaveCriteria!(criteria),
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Aramayı kaydet'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _composer(ColorScheme scheme) => Material(
    color: scheme.surface,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                maxLength: AssistantClient.maxMessage,
                buildCounter: (
                  context, {
                  required currentLength,
                  required isFocused,
                  maxLength,
                }) => null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: widget.listingTitle != null
                      ? 'Bu ilan hakkında sorun…'
                      : 'Ne tür ilanlar arıyorsunuz?',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: scheme.primary, width: 1.6),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Gönder',
              onPressed: _busy || !widget.client.available ? null : _send,
              icon: const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ],
        ),
      ),
    ),
  );
}
