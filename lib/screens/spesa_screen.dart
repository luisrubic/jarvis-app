import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';

String _euro(Object? v) => '${(v as num).toStringAsFixed(2)} €';

class SpesaScreen extends StatefulWidget {
  const SpesaScreen({super.key, required this.api});
  final Api api;

  @override
  State<SpesaScreen> createState() => _SpesaScreenState();
}

class _SpesaScreenState extends State<SpesaScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _occupato = false;
  String? _errore;
  Map<String, dynamic>? _scontrino;
  Map<String, dynamic>? _report;

  Future<void> _esegui(Future<void> Function() lavoro) async {
    setState(() {
      _occupato = true;
      _errore = null;
    });
    try {
      await lavoro();
    } on ApiErrore catch (e) {
      if (mounted) setState(() => _errore = e.messaggio);
    } finally {
      if (mounted) setState(() => _occupato = false);
    }
  }

  Future<void> _scansiona() async {
    final foto = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 85);
    if (foto == null) return;
    await _esegui(() async {
      final r = await widget.api.scontrino(foto.path);
      if (mounted) setState(() => _scontrino = r);
    });
  }

  Future<void> _mostraReport() async {
    await _esegui(() async {
      final r = await widget.api.reportMese();
      if (mounted) setState(() => _report = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('SPESA', style: tema.textTheme.headlineSmall),
        const SizedBox(height: 4),
        const Text('Fotografa lo scontrino: Jarvis legge dove, cosa e quanto, e tiene il conto del mese.'),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          onPressed: _occupato ? null : _scansiona,
          icon: const Icon(Icons.receipt_long),
          label: const Text('SCANSIONA SCONTRINO'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: _occupato ? null : _mostraReport,
          icon: const Icon(Icons.bar_chart),
          label: const Text('REPORT DEL MESE'),
        ),
        if (_occupato) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
        if (_errore != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text('⚠ $_errore', style: TextStyle(color: tema.colorScheme.error)),
          ),
        if (_scontrino != null) _cardScontrino(_scontrino!),
        if (_report != null) _cardReport(_report!),
      ],
    );
  }

  Widget _cardScontrino(Map<String, dynamic> s) {
    final prodotti = (s['prodotti'] as List).cast<Map<String, dynamic>>();
    final consigli = (s['consigli'] as List).cast<String>();
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s['negozio']}', style: Theme.of(context).textTheme.titleMedium),
            Text('${s['data']} · ${s['categoria']}'),
            if (s['gia_salvato'] == true) const Text('Scontrino già salvato in precedenza: non l\'ho contato due volte.'),
            const SizedBox(height: 8),
            for (final p in prodotti) Text('${p['nome']}   ${_euro(p['prezzo'])}'),
            const Divider(),
            Text('TOTALE ${_euro(s['totale'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
            for (final c in consigli)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text('💡 $c')),
          ],
        ),
      ),
    );
  }

  Widget _cardReport(Map<String, dynamic> r) {
    final categorie = (r['per_categoria'] as List).cast<Map<String, dynamic>>();
    final negozi = (r['per_negozio'] as List).cast<Map<String, dynamic>>();
    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Mese ${r['mese']}', style: Theme.of(context).textTheme.titleMedium),
            Text('${r['num_scontrini']} scontrini · totale ${_euro(r['totale'])}'),
            const SizedBox(height: 8),
            Text('${r['riepilogo']}'),
            if (categorie.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Per categoria', style: TextStyle(fontWeight: FontWeight.bold)),
              for (final c in categorie) Text('${c['categoria']}: ${_euro(c['totale'])}'),
            ],
            if (negozi.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Per negozio', style: TextStyle(fontWeight: FontWeight.bold)),
              for (final n in negozi) Text('${n['negozio']}: ${_euro(n['totale'])}'),
            ],
          ],
        ),
      ),
    );
  }
}
