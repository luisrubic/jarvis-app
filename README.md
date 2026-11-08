# Jarvis - App

App Flutter per Android: Jarvis (chat e voce), SOS, Lens, Spesa, Impostazioni, controllo del telefono.
Carica questa cartella in un repository GitHub: la scheda Actions compila l'APK (artifact `jarvis-apk`).

## Dopo l'installazione
1. Impostazioni: indirizzo e token del server, contatti fidati, "Concedi permessi SOS".
2. LASCIA la modalita prova accesa finche non hai provato l'SOS: non chiama e non manda SMS veri.
3. Controllo del telefono (toccare, scrivere, scorrere, leggere lo schermo): Impostazioni -> "Apri impostazioni
   accessibilita" -> Jarvis -> accendi. Se Android lo blocca: Impostazioni telefono > App > Jarvis > menu (tre puntini)
   > "Consenti impostazioni con limitazioni", poi riprova.
4. Fuori casa: installa Tailscale sul telefono (vedi README del server), poi in Impostazioni compila "Indirizzo fuori casa" e tocca
   "Prova connessione". L'app sceglie da sola tra casa e fuori casa.
5. "Ricevi i comandi chiesti dal PC": il telefono ritira ogni 5 secondi (app aperta) cio che chiedi a Jarvis dal PC.

Azioni sicure (aprire app, sveglie, timer, WhatsApp pronto, mappe, torcia, tasti di sistema, scorrere) partono subito.
Azioni delicate (chiamare, SMS, toccare, scrivere, leggere lo schermo) chiedono SEMPRE conferma con una finestra.
