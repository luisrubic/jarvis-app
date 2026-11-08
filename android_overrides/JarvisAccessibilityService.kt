package com.jarvis.jarvis_app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Servizio di accessibilità: è il "braccio" di Jarvis sul telefono (tasti di sistema, tocchi,
 * scrittura, scorrimento, lettura dello schermo). Android lo lascia attivare solo all'utente,
 * da Impostazioni > Accessibilità. Le azioni delicate le conferma l'utente dall'app (Dart).
 */
class JarvisAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var istanza: JarvisAccessibilityService? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        istanza = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        istanza = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        istanza = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    fun globale(nome: String): Boolean = when (nome) {
        "indietro" -> performGlobalAction(GLOBAL_ACTION_BACK)
        "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
        "recenti" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
        "notifiche" -> performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
        "impostazioni_rapide" -> performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)
        "blocca" -> if (Build.VERSION.SDK_INT >= 28) performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN) else false
        else -> false
    }

    /** Tocca il primo elemento che contiene il testo (o il suo genitore cliccabile). */
    fun tocca(testo: String): Boolean {
        val radice = rootInActiveWindow ?: return false
        for (nodo in radice.findAccessibilityNodeInfosByText(testo)) {
            var x: AccessibilityNodeInfo? = nodo
            while (x != null) {
                if (x.isClickable) return x.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                x = x.parent
            }
        }
        return false
    }

    /** Scrive nel campo di testo che ha il cursore. */
    fun scrivi(testo: String): Boolean {
        val radice = rootInActiveWindow ?: return false
        val campo = radice.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return false
        val args = Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, testo)
        return campo.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    fun scorri(direzione: String): Boolean {
        val radice = rootInActiveWindow ?: return false
        val nodo = trovaScorrevole(radice, 0) ?: return false
        val azione = if (direzione == "su") AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        else AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
        return nodo.performAction(azione)
    }

    private fun trovaScorrevole(nodo: AccessibilityNodeInfo, profondita: Int): AccessibilityNodeInfo? {
        if (profondita > 25) return null
        if (nodo.isScrollable) return nodo
        for (i in 0 until nodo.childCount) {
            val figlio = nodo.getChild(i) ?: continue
            val trovato = trovaScorrevole(figlio, profondita + 1)
            if (trovato != null) return trovato
        }
        return null
    }

    /** Testo visibile sullo schermo (massimo 150 elementi). */
    fun leggi(): String {
        val radice = rootInActiveWindow ?: return ""
        val righe = ArrayList<String>()
        raccogli(radice, righe, 0)
        return righe.joinToString("\n")
    }

    private fun raccogli(nodo: AccessibilityNodeInfo, righe: MutableList<String>, profondita: Int) {
        if (profondita > 25 || righe.size >= 150) return
        val t = nodo.text?.toString()?.trim().orEmpty()
        val d = nodo.contentDescription?.toString()?.trim().orEmpty()
        if (t.isNotEmpty()) righe.add(t) else if (d.isNotEmpty()) righe.add(d)
        for (i in 0 until nodo.childCount) {
            val figlio = nodo.getChild(i) ?: continue
            raccogli(figlio, righe, profondita + 1)
        }
    }
}
