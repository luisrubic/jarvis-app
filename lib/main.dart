import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/chat_screen.dart';
import 'screens/lens_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sos_screen.dart';
import 'screens/spesa_screen.dart';
import 'settings.dart';
import 'sos.dart';
import 'telefono.dart';
import 'voce.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Impostazioni.istanza.carica();
  runApp(const JarvisApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jarvis',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.cyan,
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final Impostazioni imp = Impostazioni.istanza;
  late final Voce voce = Voce();
  late final Api api = Api(imp);
  late final ServizioSos sos = ServizioSos(imp, voce);
  late final Telefono telefono = Telefono(navigatorKey, api, imp);
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    imp.addListener(_aggiornaPolling);
    _aggiornaPolling();
  }

  @override
  void dispose() {
    imp.removeListener(_aggiornaPolling);
    telefono.dispose();
    super.dispose();
  }

  void _aggiornaPolling() {
    telefono.aggiornaPolling((esiti) {
      messengerKey.currentState?.showSnackBar(SnackBar(content: Text(esiti.join('\n'))));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            ChatScreen(api: api, voce: voce, imp: imp, telefono: telefono),
            SosScreen(sos: sos, imp: imp),
            LensScreen(api: api),
            SpesaScreen(api: api),
            ImpostazioniScreen(imp: imp, sos: sos, telefono: telefono, api: api),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Jarvis'),
          NavigationDestination(icon: Icon(Icons.sos), label: 'SOS'),
          NavigationDestination(icon: Icon(Icons.camera_alt_outlined), label: 'Lens'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Spesa'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Impostazioni'),
        ],
      ),
    );
  }
}
