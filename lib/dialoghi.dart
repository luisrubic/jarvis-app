import 'package:flutter/material.dart';

/// Finestra di conferma per le azioni rischiose. Ritorna true solo se l'utente tocca "Conferma".
Future<bool> chiediConferma(BuildContext? context, String titolo, String testo) async {
  if (context == null || !context.mounted) return false;
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(titolo),
      content: Text(testo),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Conferma')),
      ],
    ),
  );
  return r ?? false;
}
