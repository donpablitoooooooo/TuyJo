package com.privatemessaging.private_messaging

import android.content.Intent
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
    private var methodChannel: MethodChannel? = null
    private var initialMediaPaths: List<String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Configura il Method Channel
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialMedia" -> {
                    result.success(initialMediaPaths)
                    initialMediaPaths = null
                }
                else -> result.notImplemented()
            }
        }

        Log.d(TAG, "Method Channel configured")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "onCreate called")

        // Gestisci i file condivisi quando l'app era chiusa
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "onNewIntent called")

        // Gestisci i file condivisi mentre l'app è aperta
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return

        Log.d(TAG, "handleIntent: action=${intent.action}, type=${intent.type}")

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

        // Se Flutter è già pronto, invia subito
        methodChannel?.let { channel ->
            Log.d(TAG, "Flutter ready, invoking onMediaShared")
            channel.invokeMethod("onMediaShared", copiedPaths)
            // Salva anche come initialMediaPaths per getInitialMedia
            initialMediaPaths = copiedPaths
        } ?: run {
            // Altrimenti salva per dopo
            Log.d(TAG, "Flutter not ready, saving as initialMediaPaths")
            initialMediaPaths = copiedPaths
        }
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
