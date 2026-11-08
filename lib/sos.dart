import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'settings.dart';
import 'voce.dart';

enum StatoSos { riposo, preallarme, inviato }

/// Tutto l'SOS funziona SOLO sul telefono (SMS, chiamata, GPS): non dipende dal server.
/// Le parti native (SMS, chiamata, vibrazione, microfono, scossa) sono in MainActivity.kt.
class ServizioSos extends ChangeNotifier {
  ServizioSos(this.imp, this.voce);
  final Impostazioni imp;
  final Voce voce;

  static const MethodChannel _nativo = MethodChannel('jarvis/native');

  StatoSos stato = StatoSos.riposo;
  int secondiRimasti = 0;
  bool ascoltando = false;
  double dbAttuale = -1000;
  double gAttuale = 0;
  final List<String> log = [];

  String _tipo = 'AGGRESSIONE';
  Timer? _preallarme;
  Timer? _ascolto;
  Timer? _gpsLive;
  bool _occupato = false;
  DateTime? _ultimoRumore;
  DateTime? _ultimaScossa;

  void _log(String s) {
    log.add(s);
    notifyListeners();
  }

  Future<void> _vibra(int ms) async {
    try {
      await _nativo.invokeMethod('vibrate', {'ms': ms});
    } catch (_) {}
  }

  // ---------------------------------------------------------------- permessi

  /// Ritorna i nomi dei permessi che mancano (lista vuota = tutto ok).
  Future<List<String>> chiediPermessi() async {
    final richieste = <Permission, String>{
      Permission.sms: 'SMS',
      Permission.phone: 'Telefono',
      Permission.microphone: 'Microfono',
      Permission.locationWhenInUse: 'Posizione',
    };
    final mancanti = <String>[];
    for (final e in richieste.entries) {
      final s = await e.key.request();
      if (!s.isGranted) mancanti.add(e.value);
    }
    return mancanti;
  }

  // ------------------------------------------------------------ pre-allarme

  /// Parte il conto alla rovescia: se non premi ANNULLA, scatta l'SOS.
  void avviaPreallarme({String tipo = 'AGGRESSIONE', int secondi = 5}) {
    if (stato != StatoSos.riposo) return;
    _tipo = tipo;
    stato = StatoSos.preallarme;
    secondiRimasti = secondi;
    log.clear();
    _vibra(400);
    _preallarme?.cancel();
    _preallarme = Timer.periodic(const Duration(seconds: 1), (t) {
      secondiRimasti--;
      if (secondiRimasti <= 0) {
        t.cancel();
        _conferma();
      } else {
        _vibra(100);
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void annulla() {
    _preallarme?.cancel();
    stato = StatoSos.riposo;
    _vibra(100);
    notifyListeners();
  }

  /// Tasto rosso tenuto premuto 2 secondi: parte subito, senza conto alla rovescia.
  void confermaSubito({String tipo = 'AGGRESSIONE'}) {
    if (stato == StatoSos.inviato) return;
    _preallarme?.cancel();
    _tipo = tipo;
    log.clear();
    _conferma();
  }

  void _conferma() {
    stato = StatoSos.inviato;
    notifyListeners();
    _esegui(_tipo);
  }

  /// Chiude la schermata dell'SOS e ferma gli aggiornamenti di posizione.
  void ferma() {
    _preallarme?.cancel();
    _gpsLive?.cancel();
    stato = StatoSos.riposo;
    notifyListeners();
  }

  // ------------------------------------------------------------- esecuzione

  Future<void> _esegui(String tipo) async {
    _log('SOS $tipo avviato${imp.modalitaProva ? ' (MODALITA PROVA: niente SMS né chiamate vere)' : ''}');
    final pos = await _posizione();
    if (pos == null) _log('Posizione non disponibile: lo scrivo nel messaggio.');
    final testo = _testoSos(tipo, pos);

    if (imp.fidati.isEmpty) _log('ATTENZIONE: nessun contatto fidato salvato.');
    for (final f in imp.fidati) {
      await _sms(f.numero, testo);
    }

    await fermaAscolto(); // libera il microfono per la registrazione
    await _registra();
    _avviaGpsLive();
    await _chiama('112');
  }

  String _link(Position p) =>
      'https://maps.google.com/?q=${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';

  // Niente accenti ed emoji: così l'SMS resta in un solo pezzo.
  String _testoSos(String tipo, Position? p) {
    final dove = p == null ? 'posizione non disponibile' : 'Posizione: ${_link(p)}';
    return 'SOS Jarvis ($tipo). Sono in pericolo. $dove. Sto chiamando il 112. Se non rispondo chiama tu il 112.';
  }

  Future<Position?> _posizione() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return await Geolocator.getLastKnownPosition();
      }
      return await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 6));
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _sms(String numero, String testo) async {
    if (imp.modalitaProva) {
      _log('[PROVA] SMS a $numero: $testo');
      return;
    }
    try {
      await _nativo.invokeMethod('sendSms', {'numero': numero, 'testo': testo});
      _log('SMS inviato a $numero');
    } on PlatformException catch (e) {
      _log('SMS NON inviato a $numero: ${e.message}');
    }
  }

  Future<void> _chiama(String numero) async {
    if (imp.modalitaProva) {
      _log('[PROVA] Avrei chiamato il $numero');
      return;
    }
    try {
      await _nativo.invokeMethod('call', {'numero': numero});
      _log('Chiamata al $numero avviata');
    } on PlatformException catch (e) {
      _log('Chiamata NON avviata: ${e.message}. Chiama tu il $numero.');
    }
  }

  Future<void> _registra() async {
    try {
      final file = await _nativo.invokeMethod<String>('record', {'secondi': 120});
      _log(file == null
          ? 'Registrazione non avviata (permesso microfono?)'
          : 'Registrazione audio 120s avviata, salvata sul telefono');
    } catch (e) {
      _log('Registrazione non avviata: $e');
    }
  }

  /// Ogni 60 secondi, per 10 minuti, rimanda la posizione ai contatti.
  /// Funziona finché l'app resta in vita: Android può fermarla se resta molto tempo in secondo piano.
  void _avviaGpsLive() {
    _gpsLive?.cancel();
    var invii = 0;
    _gpsLive = Timer.periodic(const Duration(seconds: 60), (t) async {
      invii++;
      if (invii > 10) {
        t.cancel();
        return;
      }
      final p = await _posizione();
      if (p == null) return;
      for (final f in imp.fidati) {
        await _sms(f.numero, 'Aggiornamento posizione SOS: ${_link(p)}');
      }
    });
  }

  // ----------------------------------------------------- emergenza parlata

  /// "Jarvis, emergenza": chiede il tipo a voce e poi parte il conto alla rovescia di 5 secondi.
  Future<void> emergenzaParlata() async {
    if (stato != StatoSos.riposo) return;
    await voce.parla('Che emergenza? Aggressione, medica o furto?');
    final risposta = await voce.ascolta();
    final tipo = _classifica(risposta);
    await voce.parla('Emergenza $tipo. Avviso i tuoi contatti e chiamo il 112 tra cinque secondi. Se è un errore, tocca annulla.');
    avviaPreallarme(tipo: tipo);
  }

  String _classifica(String testo) {
    final t = testo.toLowerCase();
    if (t.contains('aggress') || t.contains('picch') || t.contains('attacc')) return 'AGGRESSIONE';
    if (t.contains('medic') || t.contains('male') || t.contains('cuore') || t.contains('ambulanza')) return 'MEDICA';
    if (t.contains('furt') || t.contains('ladr') || t.contains('rapin') || t.contains('rub')) return 'FURTO';
    return 'EMERGENZA GENERICA';
  }

  // ------------------------------------------------- ascolto rumore + scossa

  /// Ritorna un messaggio di errore, o null se l'ascolto è partito.
  /// Funziona con l'app aperta e lo schermo acceso (Android blocca il microfono in background).
  Future<String?> avviaAscolto() async {
    if (ascoltando) return null;
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return 'Serve il permesso del microfono.';
    final ok = await _nativo.invokeMethod<bool>('startMic') ?? false;
    if (!ok) return 'Microfono non disponibile.';
    await _nativo.invokeMethod('startMotion');
    ascoltando = true;
    _ultimoRumore = null;
    _ultimaScossa = null;
    _ascolto = Timer.periodic(const Duration(milliseconds: 250), (_) => _controlla());
    notifyListeners();
    return null;
  }

  Future<void> fermaAscolto() async {
    _ascolto?.cancel();
    _ascolto = null;
    if (ascoltando) {
      ascoltando = false;
      try {
        await _nativo.invokeMethod('stopMic');
        await _nativo.invokeMethod('stopMotion');
      } catch (_) {}
      notifyListeners();
    }
  }

  Future<void> _controlla() async {
    if (_occupato || stato != StatoSos.riposo) return;
    _occupato = true;
    try {
      dbAttuale = (await _nativo.invokeMethod<double>('micDb')) ?? -1000;
      gAttuale = (await _nativo.invokeMethod<double>('motionG')) ?? 0;
      final ora = DateTime.now();
      if (dbAttuale >= imp.sogliaDb) _ultimoRumore = ora;
      if (gAttuale >= imp.sogliaG) _ultimaScossa = ora;
      const finestra = Duration(seconds: 3);
      final rumore = _ultimoRumore != null && ora.difference(_ultimoRumore!) < finestra;
      final scossa = _ultimaScossa != null && ora.difference(_ultimaScossa!) < finestra;
      if (imp.richiediScossa ? (rumore && scossa) : rumore) {
        _ultimoRumore = null;
        _ultimaScossa = null;
        avviaPreallarme(tipo: 'AGGRESSIONE - EMERGENZA MUTA');
      } else {
        notifyListeners();
      }
    } catch (_) {
      // un errore di lettura non deve fermare l'ascolto
    } finally {
      _occupato = false;
    }
  }
}
