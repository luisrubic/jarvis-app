"""Prepara la cartella android/ dell'app dopo `flutter create`.

Si ferma con un errore chiaro se qualcosa non va (meglio che una build rotta a metà):
1. copia i file Kotlin (MainActivity e servizio di accessibilità) e le risorse
2. aggiunge permessi, servizio di accessibilità e traffico http al AndroidManifest.xml
3. porta minSdk a 24 (serve al riconoscimento vocale)
4. mette il nome "Jarvis" all'app

Uso:  python tools/prepara_android.py android
"""
import re
import shutil
import sys
from pathlib import Path

# CAMERA non va dichiarato: image_picker usa l'app fotocamera del telefono, e un permesso
# dichiarato ma non concesso la farebbe fallire.
PERMESSI = [
    "android.permission.INTERNET", "android.permission.CALL_PHONE", "android.permission.SEND_SMS",
    "android.permission.ACCESS_FINE_LOCATION", "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.RECORD_AUDIO", "android.permission.VIBRATE",
    "com.android.alarm.permission.SET_ALARM",
]

SERVIZIO = """        <service
            android:name=".JarvisAccessibilityService"
            android:exported="true"
            android:label="Jarvis"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService"/>
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/accessibility_config"/>
        </service>
"""

QUERIES = [
    '<intent><action android:name="android.speech.RecognitionService"/></intent>',
    '<intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>',
    # per elencare le app installate e poterle aprire per nome
    '<intent><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent>',
]


def main(cartella_android):
    android = Path(cartella_android)
    main_dir = android / "app" / "src" / "main"
    overrides = Path(__file__).resolve().parent.parent / "android_overrides"
    if not overrides.is_dir():
        overrides = Path(__file__).resolve().parent.parent / "app" / "android_overrides"

    # 1. Kotlin + risorse
    esistenti = list(main_dir.glob("kotlin/**/MainActivity.kt")) + list(main_dir.glob("java/**/MainActivity.*"))
    if not esistenti:
        sys.exit("Non trovo MainActivity generata da flutter create.")
    cartella_kt = esistenti[0].parent
    pacchetto = re.search(r"^package\s+([\w.]+)", esistenti[0].read_text(encoding="utf-8"), re.M)
    if not pacchetto:
        sys.exit("Non riesco a leggere il nome del pacchetto da MainActivity.")
    for extra in esistenti[1:]:
        extra.unlink()  # se esisteva una versione Java, ne teniamo una sola
    for kt in sorted(overrides.glob("*.kt")):
        codice = re.sub(r"^package\s+[\w.]+", f"package {pacchetto.group(1)}", kt.read_text(encoding="utf-8"), count=1, flags=re.M)
        (cartella_kt / kt.name).write_text(codice, encoding="utf-8")
    if (overrides / "res").is_dir():
        shutil.copytree(overrides / "res", main_dir / "res", dirs_exist_ok=True)

    # 2. Manifest
    manifest = main_dir / "AndroidManifest.xml"
    testo = manifest.read_text(encoding="utf-8")
    if "<application" not in testo or "</application>" not in testo:
        sys.exit("AndroidManifest.xml senza <application>: formato inatteso.")
    righe = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in PERMESSI if f'"{p}"' not in testo)
    testo = testo.replace("<application", righe + "    <application", 1)
    if "usesCleartextTraffic" not in testo:
        # il server sul portatile usa http (non https) dentro la rete di casa
        testo = testo.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
    testo = re.sub(r'(<application[^>]*?android:label=")[^"]*(")', r"\1Jarvis\2", testo, count=1)
    if "JarvisAccessibilityService" not in testo:
        testo = testo.replace("</application>", SERVIZIO + "    </application>", 1)
    mancanti = [q for q in QUERIES if q not in testo]
    if mancanti:
        blocco = "".join(f"        {q}\n" for q in mancanti)
        if "</queries>" in testo:
            testo = testo.replace("</queries>", blocco + "    </queries>", 1)
        else:
            testo = testo.replace("</manifest>", "    <queries>\n" + blocco + "    </queries>\n</manifest>", 1)
    manifest.write_text(testo, encoding="utf-8")

    # 3. minSdk 24
    trovato = False
    for nome in ("build.gradle.kts", "build.gradle"):
        gradle = android / "app" / nome
        if not gradle.exists():
            continue
        g = gradle.read_text(encoding="utf-8")
        nuovo = g.replace("minSdk = flutter.minSdkVersion", "minSdk = 24").replace(
            "minSdkVersion flutter.minSdkVersion", "minSdkVersion 24")
        if nuovo != g:
            gradle.write_text(nuovo, encoding="utf-8")
            trovato = True
    if not trovato:
        print("ATTENZIONE: non ho trovato minSdk nel file gradle; se la build si lamenta di minSdk, va portato a 24.")
    print("Android pronto: codice nativo, permessi, servizio di accessibilità e manifest aggiornati.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
