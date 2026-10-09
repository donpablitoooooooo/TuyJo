package com.privatemessaging.private_messaging

import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import com.hiennv.flutter_callkit_incoming.CallkitConnection
import com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver
import com.hiennv.flutter_callkit_incoming.CallkitNotificationService
import com.hiennv.flutter_callkit_incoming.Data
import org.json.JSONArray

/**
 * Chiusura delle chiamate di sistema che NON dipende dalla lista ACTIVE_CALLS
 * di flutter_callkit_incoming.
 *
 * Il bug del Samsung di Lidia: a fine chiamata restava la notifica "Calling"
 * con "Hang up", il foreground service e la connessione Telecom (che blocca
 * le chiamate di WhatsApp). endCall/endAllCalls del plugin leggono prima
 * ACTIVE_CALLS con un ObjectMapper Jackson che rifiuta i campi sconosciuti:
 * una voce scritta dalla 3.0.0 (usata fino alla build 42) con `uuid`,
 * `isOnHold`, `audioRoute`, `isMuted` fa fallire ogni lettura, e la chiusura
 * via codice non manda niente. Il pulsante "Hang up" invece funziona perché
 * invia ACTION_CALL_ENDED con il bundle della notifica, senza leggere la lista.
 *
 * Qui: [repairActiveCalls] toglie le voci della 3.0.0 all'avvio del processo;
 * [forceEnd] fa esattamente quello che fa "Hang up".
 */
object CallkitCleanup {
    private const val TAG = "TuyJoCallkitFix"
    private const val PREFS = "flutter_callkit_incoming"
    private const val KEY = "ACTIVE_CALLS"

    /** Campi che esistono solo nelle voci scritte dal plugin 3.0.0. */
    private val LEGACY_KEYS = listOf("uuid", "isMuted", "muted", "isOnHold", "onHold", "audioRoute")

    /** Rimuove da ACTIVE_CALLS le voci illeggibili per il plugin 3.1.x. */
    fun repairActiveCalls(context: Context) {
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY, null) ?: return
            val array = try {
                JSONArray(raw)
            } catch (e: Exception) {
                prefs.edit().remove(KEY).commit()
                Log.w(TAG, "ACTIVE_CALLS illeggibile, rimossa: ${e.message}")
                return
            }
            val kept = JSONArray()
            var removed = 0
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i)
                if (item == null || LEGACY_KEYS.any { item.has(it) }) {
                    removed++
                } else {
                    kept.put(item)
                }
            }
            if (removed > 0) {
                prefs.edit().putString(KEY, kept.toString()).commit()
                Log.w(TAG, "removed $removed legacy entries from ACTIVE_CALLS")
            }
        } catch (e: Exception) {
            Log.w(TAG, "repairActiveCalls failed: ${e.message}")
        }
    }

    /**
     * Chiude la chiamata [id] come il pulsante "Hang up": ENDED al receiver
     * del plugin (Telecom disconnect + notifica + stop del servizio), più le
     * stesse operazioni fatte direttamente nel caso il broadcast non arrivi.
     * Idempotente: su una chiamata già chiusa non fa nulla di male.
     */
    fun forceEnd(context: Context, id: String) {
        if (id.isEmpty()) return
        val ctx = context.applicationContext
        try {
            val bundle = Data(mapOf("id" to id)).toBundle()
            ctx.sendBroadcast(CallkitIncomingBroadcastReceiver.getIntentEnded(ctx, bundle))
        } catch (e: Exception) {
            Log.w(TAG, "forceEnd broadcast failed: ${e.message}")
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                CallkitConnection.find(id)?.markEnded()
            }
        } catch (e: Exception) {
            Log.w(TAG, "forceEnd telecom failed: ${e.message}")
        }
        stopServiceAndNotification(ctx, id)
    }

    /**
     * Chiude tutte le chiamate risultanti ACCETTATE in ACTIVE_CALLS (lette
     * come JSON grezzo, quindi anche se la lista contiene voci della 3.0.0).
     * Le chiamate che stanno ancora squillando non vengono toccate.
     */
    fun forceEndAllAccepted(context: Context): Int {
        var ended = 0
        try {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY, null) ?: return 0
            val array = JSONArray(raw)
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                if (!item.optBoolean("isAccepted", false)) continue
                val id = item.optString("id", "")
                if (id.isNotEmpty()) {
                    forceEnd(context, id)
                    ended++
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "forceEndAllAccepted failed: ${e.message}")
        }
        return ended
    }

    private fun stopServiceAndNotification(ctx: Context, id: String) {
        try {
            CallkitNotificationService.stopService(ctx)
        } catch (e: Exception) {
            Log.w(TAG, "stopService failed: ${e.message}")
        }
        try {
            // Senza callingNotification.id la notifica in corso usa id.hashCode()
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .cancel(id.hashCode())
        } catch (e: Exception) {
            Log.w(TAG, "cancel notification failed: ${e.message}")
        }
    }
}
