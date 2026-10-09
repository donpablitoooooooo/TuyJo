package com.privatemessaging.private_messaging

import android.app.Application

/**
 * Application dell'app: all'avvio del processo ripara la lista chiamate del
 * plugin CallKit (vedi [CallkitCleanup.repairActiveCalls]).
 *
 * Deve stare qui e non in MainActivity: con l'app chiusa il processo può
 * partire da FCM o dal receiver del plugin senza mai aprire l'activity, e la
 * riparazione deve precedere la prima chiamata.
 */
class TuyJoApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        CallkitCleanup.repairActiveCalls(this)
    }
}
