import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'settings.dart';

class ApiErrore implements Exception {
  ApiErrore(this.messaggio);
  final String messaggio;
  @override
  String toString() => messaggio;
}

class RispostaChat {
  RispostaChat(this.testo, this.azioniTelefono, this.confermePc);
  final String testo;
  final List<Map<String, dynamic>> azioniTelefono;
  final List<Map<String, dynamic>> confermePc;
}

/// Parla con il server Jarvis sul portatile. La chiave Groq sta solo sul server.
/// Se ci sono due indirizzi (casa e fuori casa) usa quello che risponde.
class Api {
  Api(this.imp);
  final Impostazioni imp;

  String? _base;
  DateTime? _quando;

  static String _pulisci(String s) => s.trim().replaceAll(RegExp(r'/+$'), '');

  List<String> get _basi =>
      [_pulisci(imp.serverUrl), _pulisci(imp.serverUrlFuori)].where((s) => s.isNotEmpty).toList();

  Uri _uri(String base, String percorso, [Map<String, String>? query]) =>
      Uri.parse('$base$percorso').replace(queryParameters: query);

  Map<String, String> get _intestazioni => {'X-Token': imp.token, 'X-Client': 'app'};

  /// Sceglie l'indirizzo raggiungibile con una prova veloce (4 secondi), così la richiesta vera
  /// parte UNA volta sola: niente comandi eseguiti due volte.
  Future<String> _sceglibase() async {
    final basi = _basi;
    if (basi.isEmpty) throw ApiErrore('Scrivi l\'indirizzo del server nelle Impostazioni.');
    if (basi.length == 1) return basi.first;
    if (_base != null &&
        _quando != null &&
        basi.contains(_base) &&
        DateTime.now().difference(_quando!) < const Duration(seconds: 60)) {
      return _base!;
    }
    for (final b in basi) {
      try {
        final r = await http.get(Uri.parse('$b/stato'), headers: _intestazioni).timeout(const Duration(seconds: 4));
        if (r.statusCode == 200 || r.statusCode == 401) {
          _base = b;
          _quando = DateTime.now();
          return b;
        }
      } catch (_) {}
    }
    return basi.first;
  }

  /// Prova entrambi gli indirizzi e dice quale funziona (per il pulsante nelle Impostazioni).
  Future<String> prova() async {
    final righe = <String>[];
    for (final e in {'Casa': imp.serverUrl, 'Fuori casa': imp.serverUrlFuori}.entries) {
      final b = _pulisci(e.value);
      if (b.isEmpty) continue;
      try {
        final r = await http.get(Uri.parse('$b/stato'), headers: _intestazioni).timeout(const Duration(seconds: 6));
        final esito = r.statusCode == 200
            ? 'OK'
            : r.statusCode == 401
                ? 'raggiungibile ma il token è sbagliato'
                : 'errore ${r.statusCode}';
        righe.add('${e.key}: $esito');
      } catch (_) {
        righe.add('${e.key}: non raggiungibile');
      }
    }
    return righe.isEmpty ? 'Nessun indirizzo impostato.' : righe.join('\n');
  }

  dynamic _esito(http.Response r) {
    final corpo = utf8.decode(r.bodyBytes);
    if (r.statusCode >= 200 && r.statusCode < 300) return jsonDecode(corpo);
    var msg = 'Errore ${r.statusCode}';
    if (r.statusCode == 401) {
      msg = 'Token sbagliato: controllalo nelle Impostazioni.';
    } else {
      try {
        final d = jsonDecode(corpo);
        if (d is Map && d['detail'] != null) msg = '${d['detail']}';
      } catch (_) {}
    }
    throw ApiErrore(msg);
  }

  Future<dynamic> _conErrori(Future<http.Response> Function(String base) richiesta) async {
    final base = await _sceglibase();
    try {
      final r = await richiesta(base).timeout(const Duration(seconds: 90));
      return _esito(r);
    } on TimeoutException {
      _quando = null;
      throw ApiErrore('Il server non risponde (tempo scaduto).');
    } on SocketException {
      _quando = null;
      throw ApiErrore('Server non raggiungibile: controlla indirizzo, Wi-Fi o Tailscale e che il server sia acceso.');
    } on FormatException {
      _quando = null;
      throw ApiErrore('Indirizzo del server non valido (esempio: http://192.168.1.10:8000).');
    } on http.ClientException catch (e) {
      _quando = null;
      throw ApiErrore('Server non raggiungibile: controlla indirizzo, Wi-Fi o Tailscale e che il server sia acceso. (${e.message})');
    }
  }

  Future<dynamic> _foto(String percorso, String fileFoto) {
    return _conErrori((base) async {
      final req = http.MultipartRequest('POST', _uri(base, percorso))
        ..headers.addAll(_intestazioni)
        ..files.add(await http.MultipartFile.fromPath('foto', fileFoto));
      return http.Response.fromStream(await req.send());
    });
  }

  Future<RispostaChat> chat(String testo) async {
    final d = await _conErrori((base) => http.post(
          _uri(base, '/chat'),
          headers: {..._intestazioni, 'Content-Type': 'application/json'},
          body: jsonEncode({'testo': testo}),
        ));
    return RispostaChat(
      '${d['risposta']}',
      (d['azioni_telefono'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      (d['conferme_pc'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }

  /// Azioni per il telefono messe in coda dal server (per esempio chieste a Jarvis dal PC).
  Future<List<Map<String, dynamic>>> azioniTelefono() async {
    final d = await _conErrori((base) => http.get(_uri(base, '/telefono/azioni'), headers: _intestazioni));
    return (d['azioni'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Conferma (ok = true) o annulla un'azione rischiosa sul PC.
  Future<String> conferma(String id, bool ok) async {
    final d = await _conErrori((base) => http.post(
          _uri(base, '/conferma/$id'),
          headers: {..._intestazioni, 'Content-Type': 'application/json'},
          body: jsonEncode({'ok': ok}),
        ));
    return '${d['risultato']}';
  }

  Future<Map<String, dynamic>> lens(String fileFoto) async =>
      (await _foto('/lens', fileFoto)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> scontrino(String fileFoto) async =>
      (await _foto('/scontrino', fileFoto)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> reportMese([String? mese]) async {
    final d = await _conErrori((base) => http.get(
          _uri(base, '/spese/report', mese == null ? null : {'mese': mese}),
          headers: _intestazioni,
        ));
    return d as Map<String, dynamic>;
  }
}
