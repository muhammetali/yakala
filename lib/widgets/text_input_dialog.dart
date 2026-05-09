import 'package:flutter/material.dart';

/// Tek satır/çok satır metin girişi için Material AlertDialog.
///
/// Controller'ı kendi state'inde tutar — `dispose()` Flutter framework
/// tarafından widget tamamen ağaçtan kalktıktan **sonra** (kapanma
/// animasyonu bittiğinde) çağrılır. Yerel bir [TextEditingController]
/// oluşturup `await showDialog` sonrası `dispose()` çağırma pattern'i
/// dialog kapanma transition'ı sırasında "TextEditingController used
/// after dispose" hatasına sebep olur; bu widget o hatayı yapısal
/// olarak engeller.
///
/// Kullanım:
/// ```dart
/// final text = await TextInputDialog.show(
///   context,
///   title: 'Metin Ekle',
///   hintText: 'Görsele eklenecek metin',
/// );
/// if (text != null) {
///   // metin onaylandı (boş değil, trim'li)
/// }
/// ```
class TextInputDialog extends StatefulWidget {
  final String title;
  final String? hintText;
  final String confirmLabel;
  final String cancelLabel;
  final int minLines;
  final int maxLines;
  final String? initialValue;

  const TextInputDialog({
    super.key,
    required this.title,
    this.hintText,
    this.confirmLabel = 'Ekle',
    this.cancelLabel = 'İptal',
    this.minLines = 1,
    this.maxLines = 3,
    this.initialValue,
  });

  /// Trim edilmiş metni döndürür; iptal ya da boş giriş durumunda `null`.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String? hintText,
    String confirmLabel = 'Ekle',
    String cancelLabel = 'İptal',
    int minLines = 1,
    int maxLines = 3,
    String? initialValue,
    bool useRootNavigator = true,
  }) {
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: useRootNavigator,
      builder: (_) => TextInputDialog(
        title: title,
        hintText: hintText,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        minLines: minLines,
        maxLines: maxLines,
        initialValue: initialValue,
      ),
    );
  }

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Trim edilmiş değeri pop eder. Boş ya da yalnızca whitespace içeren
  /// girdiler `null` ile döner — caller "kullanıcı anlamlı bir şey
  /// commit etti mi" sorusunu tek not-null check ile çözebilsin diye.
  void _submit() {
    final value = _controller.text.trim();
    Navigator.of(context).pop(value.isEmpty ? null : value);
  }

  void _cancel() => Navigator.of(context).pop(null);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: widget.hintText,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: _cancel,
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
