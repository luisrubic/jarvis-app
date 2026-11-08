import 'dart:async';

import 'package:flutter/material.dart';

import '../settings.dart';
import '../sos.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key, required this.sos, required this.imp});
  final ServizioSos sos;
  final Impostazioni imp;

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  Timer? _tieni;

  @override
  void dispose() {
    _tieni?.cancel();
    super.dispose();
  }

  void _messaggio(String testo) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(testo)));
  }

  Future<void> _ascolto() async {
    final sos = widget.sos;
    if (sos.ascoltando) {
      await sos.fermaAscolto();
      return;
    }
    final errore = await sos.avviaAscolto();
    if (errore != null && mounted) _messaggio(errore);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.sos,
      builder: (context, _) {
        final sos = widget.sos;
        if (sos.stato == StatoSos.preallarme) return _preallarme(sos);
        if (sos.stato == StatoSos.inviato) return _inviato(sos);
        return _riposo(sos);
      },
    );
  }

  Widget _preallarme(ServizioSos sos) {
    return Container(
      color: Colors.red.shade900,
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('SOS TRA', style: TextStyle(fontSize: 28)),
          Text('${sos.secondiRimasti}', style: const TextStyle(fontSize: 120, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 120,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              onPressed: sos.annulla,
              child: const Text('ANNULLA\n(falso allarme)', textAlign: TextAlign.center, style: TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: sos.confermaSubito, child: const Text('Invia subito')),
        ],
      ),
    );
  }

  Widget _inviato(ServizioSos sos) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('SOS ATTIVO', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.red.shade300)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [for (final riga in sos.log) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(riga))],
            ),
          ),
          FilledButton.tonal(onPressed: sos.ferma, child: const Text('Chiudi e ferma gli aggiornamenti di posizione')),
        ],
      ),
    );
  }

  Widget _riposo(ServizioSos sos) {
    final imp = widget.imp;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (imp.modalitaProva)
          Card(
            color: Colors.amber.shade900,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('MODALITÀ PROVA: l\'SOS non chiama e non manda SMS veri. '
                  'Spegnila nelle Impostazioni quando hai finito di provare.'),
            ),
          ),
        const SizedBox(height: 12),
        GestureDetector(
          onTapDown: (_) {
            _tieni = Timer(const Duration(seconds: 2), () {
              _tieni = null;
              sos.confermaSubito();
            });
          },
          onTapUp: (_) {
            if (_tieni != null) {
              _tieni!.cancel();
              _tieni = null;
              sos.avviaPreallarme();
            }
          },
          onTapCancel: () {
            _tieni?.cancel();
            _tieni = null;
          },
          child: Container(
            height: 220,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(24)),
            child: const Text(
              'EMERGENZA MUTA\n\nTocca: parte tra 5 secondi\nTieni premuto 2 secondi: parte subito',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
          onPressed: sos.emergenzaParlata,
          icon: const Icon(Icons.record_voice_over),
          label: const Text('EMERGENZA PARLATA'),
        ),
        const SizedBox(height: 24),
        const Divider(),
        SwitchListTile(
          title: const Text('Ascolto rumore e scossa'),
          subtitle: Text(sos.ascoltando
              ? 'Attivo: ${sos.dbAttuale <= -999 ? '--' : sos.dbAttuale.toStringAsFixed(0)} dB, '
                  '${sos.gAttuale.toStringAsFixed(1)} G (soglie ${imp.sogliaDb.toStringAsFixed(0)} dB, ${imp.sogliaG.toStringAsFixed(1)} G)'
              : 'Spento. Funziona con app aperta e schermo acceso.'),
          value: sos.ascoltando,
          onChanged: (_) => _ascolto(),
        ),
        const SizedBox(height: 8),
        Text(
          imp.fidati.isEmpty
              ? 'Nessun contatto fidato: aggiungili in Impostazioni.'
              : 'Contatti avvisati: ${imp.fidati.map((f) => f.nome).join(', ')}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
