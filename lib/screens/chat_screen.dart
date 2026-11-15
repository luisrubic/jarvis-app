import 'package:flutter/material.dart';

import '../api.dart';
import '../dialoghi.dart';
import '../settings.dart';
import '../telefono.dart';
import '../voce.dart';

class _Messaggio {
  _Messaggio(this.testo, this.mio);
  final String testo;
  final bool mio;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.api, required this.voce, required this.imp, required this.telefono});
  final Telefono telefono;
  final Api api;
  final Voce voce;
  final Impostazioni imp;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<_Messaggio> _messaggi = [];
  final TextEditingController _campo = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _occupato = false;
  bool _ascolto = false;
  int _sessione = 0; // si incrementa per interrompere la conversazione vocale in corso

  @override
  void dispose() {
    _sessione++;
    widget.voce.ferma();
    widget.voce.annullaAscolto();
    _campo.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _inFondo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  /// [vocale] = il comando è arrivato a voce: dopo la risposta, se è attiva la risposta automatica,
  /// Jarvis si rimette in ascolto. Un nuovo comando interrompe subito la lettura in corso.
  Future<void> _invia(String testo, {bool vocale = false}) async {
    testo = testo.trim();
    if (testo.isEmpty || _occupato) return;
    await widget.voce.ferma(); // nuovo comando: smetti di leggere la risposta precedente
    final sessione = ++_sessione;
    _campo.clear();
    setState(() {
      _messaggi.add(_Messaggio(testo, true));
      _occupato = true;
    });
    _inFondo();
    var continua = false;
    try {
      final r = await widget.api.chat(testo);
      if (!mounted) return;
      setState(() => _messaggi.add(_Messaggio(r.testo, false)));
      if (mounted) setState(() => _occupato = false); // da qui si può già dare un nuovo comando
      final lettura = widget.imp.muto ? Future<void>.value() : widget.voce.parla(r.testo);
      await _azioni(r);
      await lettura;
      continua = vocale && widget.imp.conversazione && sessione == _sessione;
    } on ApiErrore catch (e) {
      if (!mounted) return;
      setState(() => _messaggi.add(_Messaggio('⚠ ${e.messaggio}', false)));
    } finally {
      if (mounted) setState(() => _occupato = false);
      _inFondo();
    }
    if (continua && mounted) await _parla(automatico: true);
  }

  /// Esegue le azioni decise da Jarvis: prima quelle sul telefono, poi le conferme per il PC.
  Future<void> _azioni(RispostaChat r) async {
    if (r.azioniTelefono.isNotEmpty) {
      final esiti = await widget.telefono.esegui(r.azioniTelefono);
      if (!mounted) return;
      setState(() => _messaggi.addAll(esiti.map((e) => _Messaggio(e, false))));
    }
    for (final c in r.confermePc) {
      if (!mounted) return;
      final ok = await chiediConferma(context, 'Conferma sul PC', '${c['descrizione']}');
      try {
        final esito = await widget.api.conferma('${c['id']}', ok);
        if (mounted) setState(() => _messaggi.add(_Messaggio(ok ? 'PC: $esito' : 'Annullato.', false)));
      } on ApiErrore catch (e) {
        if (mounted) setState(() => _messaggi.add(_Messaggio('⚠ ${e.messaggio}', false)));
      }
    }
  }

  /// Microfono: se Jarvis sta leggendo, lo interrompe e ti ascolta; se ti sta ascoltando, chiude
  /// l'ascolto e invia quello che ha capito.
  Future<void> _parla({bool automatico = false}) async {
    if (_ascolto) {
      await widget.voce.fermaAscolto();
      return;
    }
    final sessione = ++_sessione;
    await widget.voce.ferma();
    setState(() => _ascolto = true);
    final testo = await widget.voce.ascolta(pausa: widget.imp.pausaVoce);
    if (!mounted) return;
    setState(() => _ascolto = false);
    if (sessione != _sessione) return; // interrotto da "Ferma" o da un altro comando
    if (testo.isNotEmpty) {
      await _invia(testo, vocale: true);
    }
    // nessuna frase capita: la conversazione automatica finisce qui
  }

  /// Ferma tutto: lettura, ascolto e conversazione automatica.
  Future<void> _ferma() async {
    _sessione++;
    await widget.voce.annullaAscolto();
    await widget.voce.ferma();
    if (mounted) setState(() => _ascolto = false);
  }

  @override
  Widget build(BuildContext context) {
    final colori = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          title: const Text('JARVIS', style: TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold)),
          trailing: IconButton(
            tooltip: widget.imp.muto ? 'Voce spenta' : 'Voce accesa',
            icon: Icon(widget.imp.muto ? Icons.volume_off : Icons.volume_up),
            onPressed: () async {
              widget.imp.muto = !widget.imp.muto;
              await widget.imp.salva();
              if (mounted) setState(() {});
            },
          ),
        ),
        Expanded(
          child: _messaggi.isEmpty
              ? const Center(child: Text('Scrivi o premi il microfono.'))
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messaggi.length,
                  itemBuilder: (_, i) {
                    final m = _messaggi[i];
                    return Align(
                      alignment: m.mio ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.all(12),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                        decoration: BoxDecoration(
                          color: m.mio ? colori.primaryContainer : colori.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: SelectableText(m.testo),
                      ),
                    );
                  },
                ),
        ),
        if (_occupato) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _campo,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _invia,
                  decoration: const InputDecoration(
                    hintText: 'Parla con Jarvis…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<bool>(
                valueListenable: widget.voce.parlando,
                builder: (_, parlando, __) => (parlando || _ascolto)
                    ? IconButton.filled(
                        tooltip: 'Ferma',
                        style: IconButton.styleFrom(backgroundColor: colori.error, foregroundColor: colori.onError),
                        onPressed: _ferma,
                        icon: const Icon(Icons.stop),
                      )
                    : const SizedBox.shrink(),
              ),
              IconButton.filledTonal(
                tooltip: _ascolto ? 'Invia quello che hai detto' : 'Parla',
                onPressed: _parla,
                icon: Icon(_ascolto ? Icons.hearing : Icons.mic),
              ),
              IconButton.filled(
                onPressed: () => _invia(_campo.text),
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
