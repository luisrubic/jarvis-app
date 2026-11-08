import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Fidato {
  Fidato(this.nome, this.numero);
  final String nome;
  final String numero;

  Map<String, String> toJson() => {'nome': nome, 'numero': numero};
  factory Fidato.fromJson(Map<String, dynamic> j) =>
      Fidato('${j['nome']}', '${j['numero']}');
}

/// Impostazioni salvate sul telefono. I contatti fidati stanno QUI, non sul server,
/// così l'SOS funziona anche senza Wi-Fi e senza il portatile acceso.
class Impostazioni extends ChangeNotifier {
  Impostazioni._();
  static final Impostazioni istanza = Impostazioni._();

  late SharedPreferences _p;

  String serverUrl = 'http://192.168.1.10:8000';
  String serverUrlFuori = ''; // indirizzo Tailscale del portatile, per quando sei fuori casa
  String token = '';
  bool modalitaProva = true; // all'inizio l'SOS NON chiama e NON manda SMS veri
  bool richiediScossa = true; // rumore forte E scossa insieme
  double sogliaDb = 85;
  double sogliaG = 2.5;
  bool muto = false;
  bool riceviDalPc = false; // il telefono ritira i comandi chiesti a Jarvis dal PC
  List<Fidato> fidati = [];

  Future<void> carica() async {
    _p = await SharedPreferences.getInstance();
    serverUrl = _p.getString('serverUrl') ?? serverUrl;
    serverUrlFuori = _p.getString('serverUrlFuori') ?? serverUrlFuori;
    token = _p.getString('token') ?? token;
    modalitaProva = _p.getBool('modalitaProva') ?? true;
    richiediScossa = _p.getBool('richiediScossa') ?? true;
    sogliaDb = _p.getDouble('sogliaDb') ?? sogliaDb;
    sogliaG = _p.getDouble('sogliaG') ?? sogliaG;
    muto = _p.getBool('muto') ?? false;
    riceviDalPc = _p.getBool('riceviDalPc') ?? false;
    final grezzo = _p.getString('fidati');
    if (grezzo != null) {
      try {
        fidati = (jsonDecode(grezzo) as List)
            .map((e) => Fidato.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        fidati = [];
      }
    }
  }

  Future<void> salva() async {
    await _p.setString('serverUrl', serverUrl);
    await _p.setString('serverUrlFuori', serverUrlFuori);
    await _p.setString('token', token);
    await _p.setBool('modalitaProva', modalitaProva);
    await _p.setBool('richiediScossa', richiediScossa);
    await _p.setDouble('sogliaDb', sogliaDb);
    await _p.setDouble('sogliaG', sogliaG);
    await _p.setBool('muto', muto);
    await _p.setBool('riceviDalPc', riceviDalPc);
    await _p.setString('fidati', jsonEncode(fidati.map((f) => f.toJson()).toList()));
    notifyListeners();
  }

  /// Ritorna un messaggio di errore, o null se il contatto è stato aggiunto.
  Future<String?> aggiungiFidato(String nome, String numero) async {
    final pulito = numero.replaceAll(RegExp(r'[\s\-().]'), '');
    if (nome.trim().isEmpty) return 'Scrivi il nome.';
    if (!RegExp(r'^\+?\d{6,15}$').hasMatch(pulito)) {
      return 'Numero non valido: solo cifre, con eventuale + iniziale.';
    }
    fidati = [...fidati.where((f) => f.numero != pulito), Fidato(nome.trim(), pulito)];
    await salva();
    return null;
  }

  Future<void> rimuoviFidato(String numero) async {
    fidati = fidati.where((f) => f.numero != numero).toList();
    await salva();
  }
}
