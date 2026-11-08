package com.jarvis.jarvis_app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.AlarmClock
import android.provider.Settings
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.sqrt

/**
 * Parte nativa di Jarvis: SMS, chiamata, vibrazione, livello del microfono, scossa,
 * registrazione. Tutto quello che l'SOS deve fare anche senza server e senza internet.
 */
class MainActivity : FlutterActivity() {
    private val canale = "jarvis/native"
    private val handler = Handler(Looper.getMainLooper())

    private var mic: AudioRecord? = null
    private val bufferMic = ShortArray(8000)
    private var ultimoDb = -1000.0

    private var sensori: SensorManager? = null
    private var ascoltatore: SensorEventListener? = null
    private var maxG = 0.0

    private var registratore: MediaRecorder? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canale).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "sendSms" -> {
                        inviaSms(call.argument<String>("numero")!!, call.argument<String>("testo")!!)
                        result.success(true)
                    }
                    "call" -> {
                        chiama(call.argument<String>("numero")!!)
                        result.success(true)
                    }
                    "vibrate" -> {
                        vibra((call.argument<Int>("ms") ?: 300).toLong())
                        result.success(true)
                    }
                    "startMic" -> result.success(avviaMic())
                    "micDb" -> result.success(leggiDb())
                    "stopMic" -> {
                        fermaMic()
                        result.success(true)
                    }
                    "startMotion" -> {
                        avviaMovimento()
                        result.success(true)
                    }
                    "motionG" -> result.success(leggiG())
                    "stopMotion" -> {
                        fermaMovimento()
                        result.success(true)
                    }
                    "record" -> result.success(registra(call.argument<Int>("secondi") ?: 120))
                    "openApp" -> result.success(apriApp(call.argument<String>("nome")!!))
                    "alarm" -> {
                        impostaSveglia(call.argument<Int>("ora")!!, call.argument<Int>("minuti")!!, call.argument<String>("etichetta") ?: "")
                        result.success(true)
                    }
                    "timer" -> {
                        impostaTimer(call.argument<Int>("secondi")!!)
                        result.success(true)
                    }
                    "whatsapp" -> {
                        apriWhatsapp(call.argument<String>("numero")!!, call.argument<String>("testo") ?: "")
                        result.success(true)
                    }
                    "navigate" -> {
                        naviga(call.argument<String>("dest")!!)
                        result.success(true)
                    }
                    "torch" -> {
                        torcia(call.argument<Boolean>("on") ?: false)
                        result.success(true)
                    }
                    "a11yAttivo" -> result.success(JarvisAccessibilityService.istanza != null)
                    "a11yImpostazioni" -> {
                        val i = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(true)
                    }
                    "a11yGlobale" -> result.success(servizio().globale(call.argument<String>("azione")!!))
                    "a11yTocca" -> result.success(servizio().tocca(call.argument<String>("testo")!!))
                    "a11yScrivi" -> result.success(servizio().scrivi(call.argument<String>("testo")!!))
                    "a11yScorri" -> result.success(servizio().scorri(call.argument<String>("direzione")!!))
                    "a11yLeggi" -> result.success(servizio().leggi())
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ERRORE", e.message ?: e.toString(), null)
            }
        }
    }

    private fun haPermesso(permesso: String): Boolean =
        checkCallingOrSelfPermission(permesso) == PackageManager.PERMISSION_GRANTED


    // ---------------------------------------------------------------- controllo del telefono

    private fun servizio(): JarvisAccessibilityService =
        JarvisAccessibilityService.istanza
            ?: throw IllegalStateException("Controllo del telefono non attivo: attivalo in Impostazioni")

    private fun lancia(intent: Intent) {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    @Suppress("DEPRECATION")
    private fun apriApp(nome: String): Boolean {
        val pm = packageManager
        val elenco = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0)
        val cercato = nome.lowercase().trim()
        val trovata = elenco.firstOrNull { it.loadLabel(pm).toString().lowercase() == cercato }
            ?: elenco.firstOrNull { it.loadLabel(pm).toString().lowercase().contains(cercato) }
            ?: return false
        val intent = pm.getLaunchIntentForPackage(trovata.activityInfo.packageName) ?: return false
        lancia(intent)
        return true
    }

    private fun impostaSveglia(ora: Int, minuti: Int, etichetta: String) {
        val i = Intent(AlarmClock.ACTION_SET_ALARM)
            .putExtra(AlarmClock.EXTRA_HOUR, ora)
            .putExtra(AlarmClock.EXTRA_MINUTES, minuti)
            .putExtra(AlarmClock.EXTRA_MESSAGE, etichetta)
            .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
        lancia(i)
    }

    private fun impostaTimer(secondi: Int) {
        val i = Intent(AlarmClock.ACTION_SET_TIMER)
            .putExtra(AlarmClock.EXTRA_LENGTH, secondi)
            .putExtra(AlarmClock.EXTRA_SKIP_UI, true)
        lancia(i)
    }

    /** Apre la chat con il testo già scritto: l'invio lo premi tu. */
    private fun apriWhatsapp(numero: String, testo: String) {
        var n = numero.removePrefix("+")
        if (!numero.startsWith("+") && n.length == 10 && n.startsWith("3")) n = "39$n" // cellulare italiano
        lancia(Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/$n?text=" + Uri.encode(testo))))
    }

    private fun naviga(destinazione: String) {
        lancia(Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=" + Uri.encode(destinazione))))
    }

    private fun torcia(acceso: Boolean) {
        val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val id = cm.cameraIdList.firstOrNull {
            cm.getCameraCharacteristics(it).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        } ?: throw IllegalStateException("Questo telefono non ha la torcia")
        cm.setTorchMode(id, acceso)
    }

    // ---------------------------------------------------------------- SMS e chiamata

    @Suppress("DEPRECATION")
    private fun inviaSms(numero: String, testo: String) {
        if (!haPermesso(Manifest.permission.SEND_SMS)) throw SecurityException("Permesso SMS mancante")
        val sms: SmsManager = if (Build.VERSION.SDK_INT >= 31) {
            getSystemService(SmsManager::class.java)
        } else {
            SmsManager.getDefault()
        }
        val parti = sms.divideMessage(testo)
        sms.sendMultipartTextMessage(numero, null, parti, null, null)
    }

    @Suppress("DEPRECATION")
    private fun chiama(numero: String) {
        if (!haPermesso(Manifest.permission.CALL_PHONE)) throw SecurityException("Permesso telefono mancante")
        val intent = Intent(Intent.ACTION_CALL, Uri.fromParts("tel", numero, null))
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        // Vivavoce: tentativo "best effort", su alcuni telefoni Android lo impedisce.
        handler.postDelayed({
            try {
                val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audio.isSpeakerphoneOn = true
            } catch (e: Exception) {
            }
        }, 4000)
    }

    // ---------------------------------------------------------------- vibrazione

    @Suppress("DEPRECATION")
    private fun vibra(ms: Long) {
        val v: Vibrator = if (Build.VERSION.SDK_INT >= 31) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        if (Build.VERSION.SDK_INT >= 26) {
            v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            v.vibrate(ms)
        }
    }

    // ---------------------------------------------------------------- microfono (livello in dB stimati)

    private fun avviaMic(): Boolean {
        if (mic != null) return true
        if (!haPermesso(Manifest.permission.RECORD_AUDIO)) return false
        val minimo = AudioRecord.getMinBufferSize(16000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (minimo <= 0) return false
        val r = AudioRecord(
            MediaRecorder.AudioSource.MIC, 16000,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, max(minimo, 16000)
        )
        if (r.state != AudioRecord.STATE_INITIALIZED) {
            r.release()
            return false
        }
        r.startRecording()
        mic = r
        ultimoDb = -1000.0
        return true
    }

    /** Picco degli ultimi campioni, in dB stimati (dBFS + 95: valore indicativo, regolabile dalla soglia). */
    private fun leggiDb(): Double {
        val r = mic ?: return -1000.0
        val n = r.read(bufferMic, 0, bufferMic.size, AudioRecord.READ_NON_BLOCKING)
        if (n > 0) {
            var picco = 1
            for (i in 0 until n) picco = max(picco, abs(bufferMic[i].toInt()))
            ultimoDb = 20.0 * log10(picco / 32767.0) + 95.0
        }
        return ultimoDb
    }

    private fun fermaMic() {
        try {
            mic?.stop()
        } catch (e: Exception) {
        }
        mic?.release()
        mic = null
    }

    // ---------------------------------------------------------------- scossa

    private fun avviaMovimento() {
        if (ascoltatore != null) return
        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val sensore = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        val l = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                val g = sqrt(
                    (e.values[0] * e.values[0] + e.values[1] * e.values[1] + e.values[2] * e.values[2]).toDouble()
                ) / SensorManager.GRAVITY_EARTH
                if (g > maxG) maxG = g
            }

            override fun onAccuracyChanged(s: Sensor?, a: Int) {}
        }
        sm.registerListener(l, sensore, SensorManager.SENSOR_DELAY_GAME)
        sensori = sm
        ascoltatore = l
        maxG = 0.0
    }

    /** Massima forza (in G, a riposo vale circa 1) dall'ultima lettura. */
    private fun leggiG(): Double {
        val g = maxG
        maxG = 0.0
        return g
    }

    private fun fermaMovimento() {
        ascoltatore?.let { sensori?.unregisterListener(it) }
        ascoltatore = null
    }

    // ---------------------------------------------------------------- registrazione audio

    @Suppress("DEPRECATION")
    private fun registra(secondi: Int): String? {
        if (registratore != null) return null
        if (!haPermesso(Manifest.permission.RECORD_AUDIO)) return null
        val cartella = getExternalFilesDir(null) ?: filesDir
        val file = File(cartella, "sos_" + System.currentTimeMillis() + ".m4a")
        val mr = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(this) else MediaRecorder()
        mr.setAudioSource(MediaRecorder.AudioSource.MIC)
        mr.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        mr.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        mr.setOutputFile(file.absolutePath)
        mr.prepare()
        mr.start()
        registratore = mr
        handler.postDelayed({ fermaRegistrazione() }, secondi * 1000L)
        return file.absolutePath
    }

    private fun fermaRegistrazione() {
        try {
            registratore?.stop()
        } catch (e: Exception) {
        }
        registratore?.release()
        registratore = null
    }

    override fun onDestroy() {
        fermaMic()
        fermaMovimento()
        fermaRegistrazione()
        super.onDestroy()
    }
}
