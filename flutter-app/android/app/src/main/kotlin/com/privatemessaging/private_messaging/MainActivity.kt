package com.privatemessaging.private_messaging

import android.content.Intent
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.privatemessaging.tuyjo/shared_media"
    private val TONE_CHANNEL = "com.privatemessaging.tuyjo/tone_generator"
    private var methodChannel: MethodChannel? = null
    private var toneChannel: MethodChannel? = null
    private var toneGenerator: ToneGenerator? = null
    private var initialMediaPaths: List<String>? = null
    private var initialSharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        Log.d(TAG, "============ configureFlutterEngine called ============")
        Log.d(TAG, "Pending initialSharedText: $initialSharedText")
        Log.d(TAG, "Pending initialMediaPaths: $initialMediaPaths")

        // Configura il Method Channel
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialMedia" -> {
                    Log.d(TAG, "[FLUTTER-CALL] getInitialMedia called, returning: $initialMediaPaths")
                    result.success(initialMediaPaths)
                    initialMediaPaths = null
                }
                "getInitialSharedText" -> {
                    Log.d(TAG, "[FLUTTER-CALL] getInitialSharedText called, returning: $initialSharedText")
                    val textToReturn = initialSharedText
                    initialSharedText = null
                    result.success(textToReturn)
                    Log.d(TAG, "[FLUTTER-CALL] initialSharedText cleared")
                }
                else -> result.notImplemented()
            }
        }

        Log.d(TAG, "✅ Method Channel configured and ready")

        // ToneGenerator channel per ringback tone
        toneChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TONE_CHANNEL)
        toneChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startRingback" -> {
                    try {
                        toneGenerator?.release()
                        toneGenerator = ToneGenerator(AudioManager.STREAM_VOICE_CALL, 100)
                        // TONE_SUP_RINGTONE = ringback europeo standard (425 Hz, 1s on / 4s off)
                        toneGenerator?.startTone(ToneGenerator.TONE_SUP_RINGTONE)
                        Log.d(TAG, "🔔 ToneGenerator: ringback started")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "🔔 ToneGenerator error: ${e.message}")
                        result.error("TONE_ERROR", e.message, null)
                    }
                }
                "stopRingback" -> {
                    toneGenerator?.stopTone()
                    toneGenerator?.release()
                    toneGenerator = null
                    Log.d(TAG, "🔔 ToneGenerator: ringback stopped")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        Log.d(TAG, "✅ ToneGenerator Channel configured")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "============ onCreate called ============")
        Log.d(TAG, "Current initialSharedText: $initialSharedText")
        Log.d(TAG, "Current initialMediaPaths: $initialMediaPaths")

        // Gestisci i file condivisi quando l'app era chiusa
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "============ onNewIntent called ============")
        Log.d(TAG, "Current initialSharedText before: $initialSharedText")
        Log.d(TAG, "Current initialMediaPaths before: $initialMediaPaths")

        // IMPORTANTE: Imposta il nuovo intent come intent corrente
        setIntent(intent)

        // Gestisci i file condivisi mentre l'app è aperta
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        Log.d(TAG, "handleIntent: action=${intent.action}, type=${intent.type}")

        // Controlla prima se c'è testo condiviso (link, URL, etc.)
        if (intent.action == Intent.ACTION_SEND && intent.type?.startsWith("text/") == true) {
            intent.getStringExtra(Intent.EXTRA_TEXT)?.let { sharedText ->
                Log.d(TAG, "Shared text received: $sharedText")
                handleSharedText(sharedText)
                return
            }
        }

        // Altrimenti gestisci i file
        val uris = mutableListOf<Uri>()

        when (intent.action) {
            Intent.ACTION_SEND -> {
                // Singolo file condiviso
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uri ->
                    Log.d(TAG, "Single file received: $uri")
                    uris.add(uri)
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                // File multipli condivisi
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { list ->
                    Log.d(TAG, "Multiple files received: ${list.size}")
                    uris.addAll(list)
                }
            }
        }

        if (uris.isNotEmpty()) {
            handleSharedMedia(uris)
        }
    }

    private fun handleSharedMedia(uris: List<Uri>) {
        Log.d(TAG, "handleSharedMedia called with ${uris.size} file(s)")

        val copiedPaths = mutableListOf<String>()

        for (uri in uris) {
            Log.d(TAG, "Processing URI: $uri")
            copyFileToAppStorage(uri)?.let { path ->
                Log.d(TAG, "File copied to: $path")
                copiedPaths.add(path)
            } ?: Log.e(TAG, "Failed to copy file: $uri")
        }

        if (copiedPaths.isEmpty()) {
            Log.w(TAG, "No files were copied successfully")
            return
        }

        Log.d(TAG, "Total files copied: ${copiedPaths.size}")

        // Se Flutter è già pronto, invia subito (NON salvare in initialMediaPaths per evitare duplicazione)
        methodChannel?.let { channel ->
            Log.d(TAG, "Flutter ready, invoking onMediaShared")
            channel.invokeMethod("onMediaShared", copiedPaths)
        } ?: run {
            // Altrimenti salva per dopo
            Log.d(TAG, "Flutter not ready, saving as initialMediaPaths")
            initialMediaPaths = copiedPaths
        }
    }

    private fun handleSharedText(text: String) {
        Log.d(TAG, "========================================")
        Log.d(TAG, "[SHARED-TEXT] handleSharedText called")
        Log.d(TAG, "[SHARED-TEXT] Text: $text")
        Log.d(TAG, "[SHARED-TEXT] methodChannel is null: ${methodChannel == null}")
        Log.d(TAG, "[SHARED-TEXT] Current initialSharedText before processing: $initialSharedText")

        // Se Flutter è già pronto, invia subito (NON salvare in initialSharedText per evitare duplicazione)
        methodChannel?.let { channel ->
            Log.d(TAG, "[SHARED-TEXT] ✅ Flutter IS ready, invoking onTextShared immediately")
            channel.invokeMethod("onTextShared", text)
            Log.d(TAG, "[SHARED-TEXT] ✅ onTextShared invoked")
        } ?: run {
            // Altrimenti salva per dopo
            Log.d(TAG, "[SHARED-TEXT] ⏳ Flutter NOT ready yet, saving as initialSharedText")
            initialSharedText = text
            Log.d(TAG, "[SHARED-TEXT] ⏳ Saved. Will be retrieved by Flutter when ready.")
        }

        Log.d(TAG, "[SHARED-TEXT] Current initialSharedText after processing: $initialSharedText")
        Log.d(TAG, "========================================")
    }

    private fun copyFileToAppStorage(uri: Uri): String? {
        try {
            Log.d(TAG, "Starting copy from: $uri")

            // Ottieni il content resolver
            val inputStream = contentResolver.openInputStream(uri) ?: run {
                Log.e(TAG, "Cannot open input stream for: $uri")
                return null
            }

            // Directory cache per file condivisi
            val cacheDir = File(cacheDir, "shared_media")
            if (!cacheDir.exists()) {
                cacheDir.mkdirs()
                Log.d(TAG, "Created cache directory: ${cacheDir.absolutePath}")
            }

            // Nome file unico con timestamp
            val timestamp = System.currentTimeMillis()
            val extension = getFileExtension(uri) ?: "tmp"
            val fileName = "shared_${timestamp}.$extension"
            val destFile = File(cacheDir, fileName)

            Log.d(TAG, "Destination: ${destFile.absolutePath}")

            // Copia il file
            FileOutputStream(destFile).use { output ->
                inputStream.copyTo(output)
            }
            inputStream.close()

            Log.d(TAG, "Copy successful")
            return destFile.absolutePath

        } catch (e: Exception) {
            Log.e(TAG, "Copy error: ${e.message}", e)
            return null
        }
    }

    private fun getFileExtension(uri: Uri): String? {
        return try {
            val mimeType = contentResolver.getType(uri)
            Log.d(TAG, "MIME type: $mimeType")

            when {
                mimeType?.startsWith("image/") == true -> {
                    when (mimeType) {
                        "image/jpeg" -> "jpg"
                        "image/png" -> "png"
                        "image/gif" -> "gif"
                        "image/webp" -> "webp"
                        "image/heic" -> "heic"
                        "image/heif" -> "heif"
                        else -> "jpg"
                    }
                }
                mimeType?.startsWith("video/") == true -> {
                    when (mimeType) {
                        "video/mp4" -> "mp4"
                        "video/quicktime" -> "mov"
                        "video/x-matroska" -> "mkv"
                        "video/x-msvideo" -> "avi"
                        else -> "mp4"
                    }
                }
                mimeType == "application/pdf" -> "pdf"
                mimeType?.startsWith("application/") == true -> "bin"
                else -> {
                    // Prova a estrarre l'estensione dal path
                    contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                        if (nameIndex != -1 && cursor.moveToFirst()) {
                            val name = cursor.getString(nameIndex)
                            name.substringAfterLast('.', "tmp")
                        } else null
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting file extension: ${e.message}")
            "tmp"
        }
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
