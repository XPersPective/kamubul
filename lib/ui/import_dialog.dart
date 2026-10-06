part of '../home_page.dart';

/// Yedek JSON'unun yapıştırıldığı içe aktarma penceresi; metin denetçisi
/// kendi ömründe tutulur.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Verileri içe aktar'),
    content: TextField(
      controller: _controller,
      maxLines: 6,
      decoration: const InputDecoration(
        labelText: 'Yedek JSON',
        helperText: 'Yalnızca KamuBul yedek dosyası kabul edilir.',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Vazgeç'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('İçe aktar'),
      ),
    ],
  );
}
