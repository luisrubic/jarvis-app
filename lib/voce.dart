import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Voce di Jarvis: parla (TTS) e ascolta (riconoscimento vocale), in italiano.
class Voce {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  bool _sttPronto = false;
  bool _ttsPronto = false;

  /// Vero mentre Jarvis sta leggendo ad alta voce (serve per mostrare il pulsante "Ferma").
  final ValueNotifier<bool> parlando = ValueNotifier(false);
  Completer<void>? _interrompiLettura;

  Completer<String>? _fine;
  String _ultimo = '';
  bool _annullato = false;
  bool _fermaRichiesto = false;

  /// Toglie asterischi e simboli di formattazione, che la voce leggerebbe ad alta voce.
  static String _pulisci(String t) {
    var s = t.replaceAll(RegExp(r'```[\s\S]*?```'), ' ');
    s = s.replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1] ?? '');
    s = s.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
    s = s.replaceAll(RegExp(r'^\s*(?:[-*•+]|\d+[.)])\s+', multiLine: true), '');
    s = s.replaceAll(RegExp(r'[*`~#>|]+|(?<!\w)_+|_+(?!\w)'), '');
    s = s.replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]', unicode: true), '');
    return s.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  Future<void> _preparaTts() async {
    if (_ttsPronto) return;
    _ttsPronto = true;
    await _tts.setLanguage('it-IT');
    await _tts.awaitSpeakCompletion(true);
  }

  /// Legge il testo ad alta voce. Si può interrompere con [ferma]: in quel caso ritorna subito.
  Future<void> parla(String testo) async {
    final stop = Completer<void>();
    _interrompiLettura = stop;
    try {
      await _preparaTts();
      parlando.value = true;
      await Future.any([_tts.speak(_pulisci(testo)), stop.future]);
    } catch (_) {
      // la voce è un di più: se non funziona non deve bloccare nulla
    } finally {
      if (identical(_interrompiLettura, stop)) _interrompiLettura = null;
      parlando.value = false;
    }
  }

  /// Interrompe subito la lettura.
  Future<void> ferma() async {
    final stop = _interrompiLettura;
    if (stop != null && !stop.isCompleted) stop.complete();
    parlando.value = false;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void _chiudiSegmento() {
    final f = _fine;
    if (f != null && !f.isCompleted) f.complete(_ultimo);
  }

  /// Un singolo tratto di ascolto. Ritorna le parole capite fino a quel momento.
  Future<String> _segmento(int secondi) async {
    final fine = Completer<String>();
    _fine = fine;
    _ultimo = '';
    await _stt.listen(
      localeId: 'it_IT',
      listenFor: Duration(seconds: secondi),
      pauseFor: Duration(seconds: min(secondi, 6)),
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: false),
      onResult: (r) {
        _ultimo = r.recognizedWords;
        if (r.finalResult) _chiudiSegmento();
      },
    );
    return fine.future.timeout(
      Duration(seconds: secondi + 3),
      onTimeout: () {
        _stt.stop();
        return _ultimo;
      },
    );
  }

  /// Ascolta fino a [secondi] in tutto. Dopo ogni frase aspetta ancora [pausa] secondi di silenzio
  /// prima di darla per finita, così puoi fare pause nel comando. Ritorna '' se non senti nulla.
  /// Si può chiudere prima con [fermaAscolto] (invia quello che ha capito) o [annullaAscolto] (scarta).
  Future<String> ascolta({int secondi = 30, int pausa = 4}) async {
    try {
      await ferma();
      if (!_sttPronto) {
        _sttPronto = await _stt.initialize(onStatus: (s) {
          if (s == 'done' || s == 'notListening') _chiudiSegmento();
        });
      }
      if (!_sttPronto) return '';
      _annullato = false;
      _fermaRichiesto = false;
      final totale = StringBuffer();
      final limite = DateTime.now().add(Duration(seconds: secondi));
      while (!_annullato && DateTime.now().isBefore(limite)) {
        final restante = max(1, limite.difference(DateTime.now()).inSeconds);
        final durata = totale.isEmpty ? restante : min(pausa, restante);
        final inizio = DateTime.now();
        final parole = (await _segmento(durata)).trim();
        if (_annullato) return '';
        if (parole.isNotEmpty) totale.write(totale.isEmpty ? parole : ' $parole');
        if (_fermaRichiesto) break;
        if (parole.isEmpty && totale.isNotEmpty) break; // silenzio dopo il comando: fine
        if (parole.isEmpty && DateTime.now().difference(inizio).inMilliseconds < 700) break; // errore immediato
      }
      return _annullato ? '' : totale.toString().trim();
    } catch (_) {
      return '';
    }
  }

  /// Chiude l'ascolto e usa quello che ha capito finora.
  Future<void> fermaAscolto() async {
    _fermaRichiesto = true;
    try {
      await _stt.stop();
    } catch (_) {}
    _chiudiSegmento();
  }

  /// Chiude l'ascolto e scarta tutto.
  Future<void> annullaAscolto() async {
    _annullato = true;
    try {
      await _stt.cancel();
    } catch (_) {}
    _chiudiSegmento();
  }
}
