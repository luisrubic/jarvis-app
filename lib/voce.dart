import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Voce di Jarvis: parla (TTS) e ascolta (riconoscimento vocale), in italiano.
class Voce {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  bool _sttPronto = false;

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

  Future<void> parla(String testo) async {
    try {
      await _tts.setLanguage('it-IT');
      await _tts.awaitSpeakCompletion(true);
      await _tts.speak(_pulisci(testo));
    } catch (_) {
      // la voce è un di più: se non funziona non deve bloccare nulla
    }
  }

  /// Ascolta per al massimo [secondi] e ritorna il testo ('' se non ha capito nulla).
  Future<String> ascolta({int secondi = 6}) async {
    try {
      if (!_sttPronto) _sttPronto = await _stt.initialize();
      if (!_sttPronto) return '';
      final fine = Completer<String>();
      await _stt.listen(
        localeId: 'it_IT',
        listenFor: Duration(seconds: secondi),
        pauseFor: const Duration(seconds: 3),
        onResult: (r) {
          if (r.finalResult && !fine.isCompleted) fine.complete(r.recognizedWords);
        },
      );
      return await fine.future.timeout(
        Duration(seconds: secondi + 3),
        onTimeout: () {
          _stt.stop();
          return '';
        },
      );
    } catch (_) {
      return '';
    }
  }
}
