import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';

class LensScreen extends StatefulWidget {
  const LensScreen({super.key, required this.api});
  final Api api;

  @override
  State<LensScreen> createState() => _LensScreenState();
}

class _LensScreenState extends State<LensScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _occupato = false;
  String? _errore;
  String? _prodotto;
  bool _incerto = false;
  List<Map<String, dynamic>> _negozi = [];

  Future<void> _scatta() async {
    final foto = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85);
    if (foto == null) return;
    setState(() {
      _occupato = true;
      _errore = null;
    });
    try {
      final r = await widget.api.lens(foto.path);
      if (!mounted) return;
      setState(() {
        _prodotto = '${r['prodotto']}';
        _incerto = r['incerto'] == true;
        _negozi = (r['negozi'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } on ApiErrore catch (e) {
      if (mounted) setState(() => _errore = e.messaggio);
    } finally {
      if (mounted) setState(() => _occupato = false);
    }
  }

  Future<void> _apri(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Non riesco ad aprire il link.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('LENS', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text('Fotografa un prodotto: Jarvis lo riconosce e ti apre la ricerca sui negozi.'),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          onPressed: _occupato ? null : _scatta,
          icon: const Icon(Icons.camera_alt),
          label: const Text('SCATTA PRODOTTO'),
        ),
        if (_occupato) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
        if (_errore != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text('⚠ $_errore', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        if (_prodotto != null) ...[
          const SizedBox(height: 24),
          Text(_prodotto!, style: Theme.of(context).textTheme.titleLarge),
          if (_incerto) const Text('Riconoscimento incerto: controlla il nome prima di cercare.'),
          const SizedBox(height: 4),
          const Text('Apri un negozio per vedere i prezzi aggiornati.'),
          const SizedBox(height: 8),
          for (final n in _negozi)
            Card(
              child: ListTile(
                title: Text('${n['negozio']}'),
                trailing: const Text('VAI >'),
                onTap: () => _apri('${n['url']}'),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => Share.share('Guarda $_prodotto: ${_negozi.isNotEmpty ? _negozi.first['url'] : ''}'),
            icon: const Icon(Icons.share),
            label: const Text('Condividi'),
          ),
        ],
      ],
    );
  }
}
