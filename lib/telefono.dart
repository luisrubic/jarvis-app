import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'dialoghi.dart';
import 'settings.dart';

/// Esegue sul telefono le azioni decise da Jarvis. Quelle con rischio "alto" (chiamare, SMS,
/// toccare, scrivere, leggere lo schermo) mostrano una finestra di conferma: il testo lo scrive
/// il server dai parametri veri, quindi vedi esattamente cosa sta per succedere.
class Telefono {
  Telefono(this.navKey, this.api, this.imp);
  final GlobalKey<NavigatorState> navKey;
  final Api api;
  final Impostazioni imp;

  static const MethodChannel _n = MethodChannel('jarvis/native');
  Timer? _poll;
  bool _inCorso = false;

  Future<bool> controlloAttivo() async {
    try {
      return await _n.invokeMethod<bool>('a11yAttivo') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> apriImpostazioniAccessibilita() => _n.invokeMethod('a11yImpostazioni');

  /// Ritorna una riga di esito per ogni azione.
  Future<List<String>> esegui(List<Map<String, dynamic>> azioni) async {
    final esiti = <String>[];
    for (final a in azioni) {
      final descrizione = '${a['descrizione']}';
      if (a['rischio'] == 'alto') {
        final ok = await chiediConferma(navKey.currentContext, 'Jarvis chiede il permesso', descrizione);
        if (!ok) {
          esiti.add('Annullato: $descrizione');
          continue;
        }
      }
      esiti.add(await _una(a));
    }
    return esiti;
  }

  static const _serveAccessibilita = {'globale', 'tocca', 'scrivi', 'scorri', 'leggi'};

  Future<String> _una(Map<String, dynamic> a) async {
    final tipo = '${a['tipo']}';
    final args = Map<String, dynamic>.from(a['args'] as Map? ?? {});
    try {
      if (_serveAccessibilita.contains(tipo) && !await controlloAttivo()) {
        return 'Controllo del telefono non attivo: attivalo in Impostazioni.';
      }
      switch (tipo) {
        case 'apri_app':
          final ok = await _n.invokeMethod<bool>('openApp', {'nome': args['nome']}) ?? false;
          return ok ? 'Aperta l\'app ${args['nome']}' : 'Non trovo l\'app ${args['nome']}';
        case 'sveglia':
          await _n.invokeMethod('alarm', {'ora': args['ora'], 'minuti': args['minuti'], 'etichetta': args['etichetta'] ?? ''});
          return 'Sveglia impostata';
        case 'timer':
          await _n.invokeMethod('timer', {'secondi': args['secondi']});
          return 'Timer avviato';
        case 'whatsapp':
          await _n.invokeMethod('whatsapp', {'numero': args['numero'], 'testo': args['testo']});
          return 'WhatsApp pronto: premi tu invio';
        case 'naviga':
          await _n.invokeMethod('navigate', {'dest': args['destinazione']});
          return 'Navigazione aperta';
        case 'torcia':
          await _n.invokeMethod('torch', {'on': args['acceso']});
          return args['acceso'] == true ? 'Torcia accesa' : 'Torcia spenta';
        case 'chiama':
          await _n.invokeMethod('call', {'numero': args['numero']});
          return 'Chiamata avviata';
        case 'sms':
          await _n.invokeMethod('sendSms', {'numero': args['numero'], 'testo': args['testo']});
          return 'SMS inviato';
        case 'globale':
          final ok = await _n.invokeMethod<bool>('a11yGlobale', {'azione': args['azione']}) ?? false;
          return ok ? 'Fatto: ${args['azione']}' : 'Non riuscito: ${args['azione']}';
        case 'tocca':
          final ok = await _n.invokeMethod<bool>('a11yTocca', {'testo': args['testo']}) ?? false;
          return ok ? 'Toccato "${args['testo']}"' : 'Non trovo "${args['testo']}" sullo schermo';
        case 'scrivi':
          final ok = await _n.invokeMethod<bool>('a11yScrivi', {'testo': args['testo']}) ?? false;
          return ok ? 'Testo scritto' : 'Nessun campo di testo attivo';
        case 'scorri':
          final ok = await _n.invokeMethod<bool>('a11yScorri', {'direzione': args['direzione']}) ?? false;
          return ok ? 'Scorso' : 'Niente da scorrere';
        case 'leggi':
          final t = await _n.invokeMethod<String>('a11yLeggi') ?? '';
          return t.isEmpty ? 'Lo schermo non ha testo leggibile' : 'Sullo schermo:\n$t';
        default:
          return 'Azione sconosciuta: $tipo';
      }
    } on PlatformException catch (e) {
      return 'Errore: ${e.message}';
    }
  }

  // ---- comandi chiesti a Jarvis dal PC: il telefono li ritira ogni 5 secondi (solo app aperta)

  void aggiornaPolling(void Function(List<String>) suEsiti) {
    _poll?.cancel();
    _poll = null;
    if (!imp.riceviDalPc) return;
    _poll = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_inCorso) return;
      _inCorso = true;
      try {
        final azioni = await api.azioniTelefono();
        if (azioni.isNotEmpty) suEsiti(await esegui(azioni));
      } catch (_) {
        // server spento o rete assente: riprova al prossimo giro
      } finally {
        _inCorso = false;
      }
    });
  }

  void dispose() => _poll?.cancel();
}
