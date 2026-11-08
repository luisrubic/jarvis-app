import 'package:flutter/material.dart';

import '../api.dart';
import '../settings.dart';
import '../sos.dart';
import '../telefono.dart';

class ImpostazioniScreen extends StatefulWidget {
  const ImpostazioniScreen({super.key, required this.imp, required this.sos, required this.telefono, required this.api});
  final Api api;
  final Telefono telefono;
  final Impostazioni imp;
  final ServizioSos sos;

  @override
  State<ImpostazioniScreen> createState() => _ImpostazioniScreenState();
}

class _ImpostazioniScreenState extends State<ImpostazioniScreen> {
  late final TextEditingController _url = TextEditingController(text: widget.imp.serverUrl);
  late final TextEditingController _urlFuori = TextEditingController(text: widget.imp.serverUrlFuori);
  late final TextEditingController _token = TextEditingController(text: widget.imp.token);
  late final TextEditingController _casa = TextEditingController(text: widget.imp.indirizzoCasa);
  late final TextEditingController _lavoro = TextEditingController(text: widget.imp.indirizzoLavoro);
  final TextEditingController _nome = TextEditingController();
  final TextEditingController _numero = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _urlFuori.dispose();
    _casa.dispose();
    _lavoro.dispose();
    _token.dispose();
    _nome.dispose();
    _numero.dispose();
    super.dispose();
  }

  bool _controlloAttivo = false;

  @override
  void initState() {
    super.initState();
    _aggiornaControllo();
  }

  Future<void> _aggiornaControllo() async {
    final attivo = await widget.telefono.controlloAttivo();
    if (mounted) setState(() => _controlloAttivo = attivo);
  }

  void _avviso(String testo) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(testo)));
  }

  Future<void> _aggiungi() async {
    final errore = await widget.imp.aggiungiFidato(_nome.text, _numero.text);
    if (errore != null) {
      _avviso(errore);
      return;
    }
    _nome.clear();
    _numero.clear();
  }

  Future<void> _permessi() async {
    final mancanti = await widget.sos.chiediPermessi();
    if (!mounted) return;
    _avviso(mancanti.isEmpty ? 'Tutti i permessi concessi.' : 'Mancano: ${mancanti.join(', ')}');
  }

  @override
  Widget build(BuildContext context) {
    final imp = widget.imp;
    return ListenableBuilder(
      listenable: imp,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('IMPOSTAZIONI', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const Text('Server Jarvis (il portatile)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Indirizzo',
              helperText: 'Esempio: http://192.168.1.10:8000 (IP del portatile, stesso Wi-Fi)',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              imp.serverUrl = v;
              imp.salva();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlFuori,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Indirizzo fuori casa (Tailscale, facoltativo)',
              helperText: 'Esempio: http://100.101.102.103:8000 (IP Tailscale del portatile)',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              imp.serverUrlFuori = v;
              imp.salva();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Token (JARVIS_TOKEN del server)',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              imp.token = v;
              imp.salva();
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              _avviso('Provo la connessione…');
              final esito = await widget.api.prova();
              if (mounted) _avviso(esito);
            },
            icon: const Icon(Icons.wifi_find),
            label: const Text('Prova connessione'),
          ),
          const Divider(height: 40),
          const Text('I miei indirizzi', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _casa,
            keyboardType: TextInputType.streetAddress,
            decoration: const InputDecoration(
              labelText: 'Indirizzo di casa',
              helperText: 'Per "Jarvis, portami a casa". Esempio: Via Roma 10, Milano',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              imp.indirizzoCasa = v;
              imp.salva();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lavoro,
            keyboardType: TextInputType.streetAddress,
            decoration: const InputDecoration(
              labelText: 'Indirizzo di lavoro (facoltativo)',
              helperText: 'Per "portami al lavoro"',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              imp.indirizzoLavoro = v;
              imp.salva();
            },
          ),
          const Divider(height: 40),
          const Text('SOS', style: TextStyle(fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: const Text('Modalità prova'),
            subtitle: const Text('Acceso: l\'SOS NON chiama il 112 e NON manda SMS veri. Spegnila solo dopo aver provato.'),
            value: imp.modalitaProva,
            onChanged: (v) {
              imp.modalitaProva = v;
              imp.salva();
            },
          ),
          SwitchListTile(
            title: const Text('Rumore forte E scossa insieme'),
            subtitle: const Text('Spento: basta un rumore forte (più falsi allarmi).'),
            value: imp.richiediScossa,
            onChanged: (v) {
              imp.richiediScossa = v;
              imp.salva();
            },
          ),
          ListTile(
            title: Text('Soglia rumore: ${imp.sogliaDb.toStringAsFixed(0)} dB'),
            subtitle: Slider(
              min: 60,
              max: 100,
              divisions: 40,
              value: imp.sogliaDb,
              onChanged: (v) {
                imp.sogliaDb = v;
                imp.salva();
              },
            ),
          ),
          ListTile(
            title: Text('Soglia scossa: ${imp.sogliaG.toStringAsFixed(1)} G'),
            subtitle: Slider(
              min: 1.5,
              max: 4,
              divisions: 25,
              value: imp.sogliaG,
              onChanged: (v) {
                imp.sogliaG = v;
                imp.salva();
              },
            ),
          ),
          const Text(
            'I dB del telefono sono una stima: dalla schermata SOS accendi l\'ascolto, fai un rumore forte vicino al telefono e regola la soglia guardando il valore letto.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _permessi,
            icon: const Icon(Icons.verified_user),
            label: const Text('Concedi permessi SOS (SMS, telefono, microfono, posizione)'),
          ),
          const Divider(height: 40),
          const Text('Controllo del telefono', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(_controlloAttivo
              ? 'Attivo: Jarvis può premere i tasti di sistema, toccare, scrivere, scorrere e leggere lo schermo. '
                  'Le azioni delicate ti chiedono sempre conferma.'
              : 'Spento. Per attivarlo: tocca il pulsante, scegli "Jarvis" e accendilo. Se Android lo blocca '
                  '("impostazione con limitazioni"): Impostazioni > App > Jarvis > menu ⋮ > Consenti impostazioni con limitazioni.'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await widget.telefono.apriImpostazioniAccessibilita();
                  },
                  icon: const Icon(Icons.accessibility_new),
                  label: const Text('Apri impostazioni accessibilità'),
                ),
              ),
              IconButton(onPressed: _aggiornaControllo, icon: const Icon(Icons.refresh)),
            ],
          ),
          SwitchListTile(
            title: const Text('Ricevi i comandi chiesti dal PC'),
            subtitle: const Text('Il telefono controlla il server ogni 5 secondi (solo con app aperta) ed esegue ciò che chiedi a Jarvis dal PC.'),
            value: imp.riceviDalPc,
            onChanged: (v) {
              imp.riceviDalPc = v;
              imp.salva();
            },
          ),
          const Divider(height: 40),
          const Text('Contatti fidati', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(controller: _nome, decoration: const InputDecoration(labelText: 'Nome', border: OutlineInputBorder())),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _numero,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Numero', border: OutlineInputBorder()),
                ),
              ),
              IconButton.filled(onPressed: _aggiungi, icon: const Icon(Icons.add)),
            ],
          ),
          for (final f in imp.fidati)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(f.nome),
              subtitle: Text(f.numero),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => imp.rimuoviFidato(f.numero),
              ),
            ),
        ],
      ),
    );
  }
}
