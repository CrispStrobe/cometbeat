// lib/shared/widgets/text_prompt_dialog.dart
//
// "Name this" — one text field in a dialog, returning what was typed.
//
// Exists because the obvious shape is wrong: creating a TextEditingController
// before `showDialog` and disposing it when the await returns. The dialog is
// still animating out at that point, and its exit frames rebuild the TextField
// against the controller that was just disposed — a throw on exactly that
// frame, which is why the pattern survives casual use (WS-W6 found it, the
// chart library's tag editor hit it again). Here the dialog's own State owns
// the controller, so it lives exactly as long as the dialog does.

import 'package:flutter/material.dart';

/// Asks for one line of text. Returns it (untrimmed), or null if cancelled.
///
/// [cancelLabel] null shows no cancel button (a tap outside still cancels).
/// [accept] keeps the dialog open while it returns false (an out-of-range
/// number, say). [label] is a floating label, [hint] placeholder text.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? cancelLabel,
  String initial = '',
  String? hint,
  String? label,
  int? maxLength,
  int maxLines = 1,
  TextInputType? keyboardType,
  bool Function(String text)? accept,
  Key? fieldKey,
  Key? confirmKey,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextPromptDialog(
        title: title,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        initial: initial,
        hint: hint,
        label: label,
        maxLength: maxLength,
        maxLines: maxLines,
        keyboardType: keyboardType,
        accept: accept,
        fieldKey: fieldKey,
        confirmKey: confirmKey,
      ),
    );

class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.initial,
    required this.hint,
    required this.label,
    required this.maxLength,
    required this.maxLines,
    required this.keyboardType,
    required this.accept,
    required this.fieldKey,
    required this.confirmKey,
  });

  final String title;
  final String confirmLabel;
  final String? cancelLabel;
  final String initial;
  final String? hint;
  final String? label;
  final int? maxLength;
  final int maxLines;
  final TextInputType? keyboardType;
  final bool Function(String text)? accept;
  final Key? fieldKey;
  final Key? confirmKey;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm(String text) {
    if (widget.accept?.call(text) ?? true) Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          key: widget.fieldKey,
          controller: _controller,
          autofocus: true,
          maxLength: widget.maxLength,
          maxLines: widget.maxLines,
          keyboardType: widget.keyboardType,
          decoration: InputDecoration(
            hintText: widget.hint,
            labelText: widget.label,
          ),
          onSubmitted: _confirm,
        ),
        actions: [
          if (widget.cancelLabel != null)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(widget.cancelLabel!),
            ),
          TextButton(
            key: widget.confirmKey,
            onPressed: () => _confirm(_controller.text),
            child: Text(widget.confirmLabel),
          ),
        ],
      );
}
