import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../models/message.dart';
import '../services/attachment_service.dart';
import '../services/location_service.dart';
import '../screens/pdf_viewer_screen.dart';

/// Widget per visualizzare allegati immagine (decifrato)
class AttachmentImage extends StatefulWidget {
  final Attachment attachment;
  final bool isMe;
  final String? currentUserId;
  final String? senderId;
  final AttachmentService attachmentService;

  const AttachmentImage({
    super.key,
    required this.attachment,
    required this.isMe,
    this.currentUserId,
    this.senderId,
    required this.attachmentService,
  });

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  late Future<Uint8List?> _imageFuture;

  @override
  void initState() {
    super.initState();
    // Crea il Future solo una volta - non verrà ricreato al rebuild
    _imageFuture = _loadImage();
  }

  @override
  void didUpdateWidget(AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ricrea il Future SOLO se l'URL dell'attachment è cambiato
    // (es. da vuoto a pieno quando il messaggio passa da pending a reale)
    if (oldWidget.attachment.url != widget.attachment.url) {
      if (kDebugMode) {
        print('📸 [AttachmentImage] URL changed, reloading image');
        print('   Old URL: ${oldWidget.attachment.url.isEmpty ? "(empty)" : "present"}');
        print('   New URL: ${widget.attachment.url.isEmpty ? "(empty)" : "present"}');
      }
      _imageFuture = _loadImage();
    }
  }

  Future<Uint8List?> _loadImage() {
    // Se URL è vuoto, l'attachment è ancora in upload - ritorna null
    if (widget.attachment.url.isEmpty) {
      return Future.value(null);
    }

    return widget.attachmentService.downloadAndDecryptAttachment(
      widget.attachment,
      widget.currentUserId ?? '',
      widget.senderId ?? '',
      useThumbnail: true, // Usa thumbnail per performance
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Se URL è vuoto, l'allegato è in upload - mostra placeholder
    if (widget.attachment.url.isEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 200,
          height: 200,
          color: widget.isMe ? Colors.white.withOpacity(0.1) : Colors.grey[200],
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  l10n.chatLoadingAttachment,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        // Apri fullscreen image viewer
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => FullscreenImageViewer(
              attachment: widget.attachment,
              attachmentService: widget.attachmentService,
              currentUserId: widget.currentUserId,
              senderId: widget.senderId,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FutureBuilder<Uint8List?>(
          future: _imageFuture, // Usa il Future cachato
          builder: (context, snapshot) {
            if (kDebugMode) {
              print('📸 [AttachmentImage] State: ${snapshot.connectionState}');
              print('  - hasError: ${snapshot.hasError}');
              print('  - hasData: ${snapshot.hasData}');
              print('  - data size: ${snapshot.data?.length ?? 0}');
              if (snapshot.hasError) {
                print('  - error: ${snapshot.error}');
              }
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              // Caricamento
              return Container(
                width: 200,
                height: 200,
                color: widget.isMe ? Colors.white.withOpacity(0.1) : Colors.grey[200],
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
              // Errore decifratura
              return Container(
                width: 200,
                height: 200,
                color: Colors.red.withOpacity(0.1),
                child: const Center(
                  child: Icon(Icons.error, color: Colors.red),
                ),
              );
            }

            // Immagine decifrata visualizzata - box quadrato 200x200 (matcha thumbnail 300x300)
            return SizedBox(
              width: 200,
              height: 200,
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.cover, // Aspect ratio 1:1 → nessuna deformazione
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Widget per visualizzare allegati video (cifrato - placeholder)
class AttachmentVideo extends StatelessWidget {
  final Attachment attachment;
  final bool isMe;
  final String? currentUserId;
  final String? senderId;

  const AttachmentVideo({
    super.key,
    required this.attachment,
    required this.isMe,
    this.currentUserId,
    this.senderId,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Per i video cifrati, mostriamo solo un placeholder
    // TODO: Implementare video player per video cifrati
    return GestureDetector(
      onTap: () {
        // TODO: Scaricare, decifrare e aprire video player
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.chatVideoPlayerInDevelopment),
          ),
        );
      },
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isMe ? Colors.white.withOpacity(0.1) : Colors.grey[200],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 32,
              ),
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.videocam, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      attachment.fileName,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget per visualizzare allegati documento (cifrato - placeholder)
class AttachmentDocument extends StatefulWidget {
  final Attachment attachment;
  final bool isMe;
  final String? currentUserId;
  final String? senderId;
  final AttachmentService attachmentService;

  const AttachmentDocument({
    super.key,
    required this.attachment,
    required this.isMe,
    this.currentUserId,
    this.senderId,
    required this.attachmentService,
  });

  @override
  State<AttachmentDocument> createState() => _AttachmentDocumentState();
}

class _AttachmentDocumentState extends State<AttachmentDocument> {
  bool _isDownloading = false;

  Future<void> _openDocument() async {
    if (_isDownloading) return;

    // Se URL è vuoto, il documento è ancora in upload - non fare nulla
    if (widget.attachment.url.isEmpty) return;

    // Check if it's a PDF - open with integrated viewer
    final isPdf = widget.attachment.fileName.toLowerCase().endsWith('.pdf');

    if (isPdf) {
      // Open PDF with integrated viewer
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PdfViewerScreen(
              attachment: widget.attachment,
              attachmentService: widget.attachmentService,
              currentUserId: widget.currentUserId,
              senderId: widget.senderId,
            ),
          ),
        );
      }
      return;
    }

    // For non-PDF documents, download and open with external app
    setState(() => _isDownloading = true);

    try {
      // 1. Download and decrypt document
      final decryptedBytes = await widget.attachmentService.downloadAndDecryptAttachment(
        widget.attachment,
        widget.currentUserId ?? '',
        widget.senderId ?? '',
        useThumbnail: false,
      );

      if (decryptedBytes == null) {
        throw Exception('Failed to download document');
      }

      // 2. Save to temporary directory
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${widget.attachment.fileName}');
      await file.writeAsBytes(decryptedBytes);

      // 3. Open with external app
      final result = await OpenFilex.open(file.path);

      if (result.type != ResultType.done && mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.chatFileOpenError(result.message)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error opening document: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.error(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: _openDocument,
      child: Container(
        constraints: const BoxConstraints(minWidth: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: widget.isMe ? Colors.white.withOpacity(0.1) : Colors.grey[200],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: widget.isMe ? Colors.white.withOpacity(0.2) : Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
              child: (_isDownloading || widget.attachment.url.isEmpty)
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.isMe ? Colors.white : Colors.grey[700]!,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.insert_drive_file,
                      color: widget.isMe ? Colors.white : Colors.grey[700],
                    ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.attachment.fileName,
                    style: TextStyle(
                      color: widget.isMe ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.attachment.url.isEmpty
                        ? l10n.chatLoadingAttachment
                        : widget.attachmentService.formatFileSize(widget.attachment.fileSize),
                    style: TextStyle(
                      color: widget.isMe ? Colors.white70 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.lock_outline,
              size: 16,
              color: widget.isMe ? Colors.white70 : Colors.black54,
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget per visualizzare immagine a schermo intero con zoom
class FullscreenImageViewer extends StatefulWidget {
  final Attachment attachment;
  final AttachmentService attachmentService;
  final String? currentUserId;
  final String? senderId;

  const FullscreenImageViewer({
    super.key,
    required this.attachment,
    required this.attachmentService,
    this.currentUserId,
    this.senderId,
  });

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  bool _showOverlay = true;

  void _toggleOverlay() {
    setState(() {
      _showOverlay = !_showOverlay;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleOverlay,
        child: Stack(
          children: [
            // Immagine full screen con zoom
            Center(
              child: FutureBuilder<Uint8List?>(
                future: widget.attachmentService.downloadAndDecryptAttachment(
                  widget.attachment,
                  widget.currentUserId ?? '',
                  widget.senderId ?? '',
                  useThumbnail: false, // Carica immagine FULL RESOLUTION
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    // Loading
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          l10n.chatLoadingImage,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    );
                  }

                  if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                    // Errore
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          l10n.chatImageLoadError,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    );
                  }

                  // Immagine decifrata con zoom
                  return InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.memory(
                      snapshot.data!,
                      fit: BoxFit.contain,
                    ),
                  );
                },
              ),
            ),

            // Overlay con animazione fade (pulsante chiudi in alto a destra)
            AnimatedOpacity(
              opacity: _showOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 32),
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withOpacity(0.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Overlay con animazione fade (info file in basso)
            AnimatedOpacity(
              opacity: _showOverlay ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.attachment.fileName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock, color: Colors.white70, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'Cifrato E2E • ${widget.attachmentService.formatFileSize(widget.attachment.fileSize)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget per visualizzare allegato condivisione posizione
class AttachmentLocationShare extends StatelessWidget {
  final Message message;
  final bool isMe;
  final VoidCallback onTap;

  const AttachmentLocationShare({
    Key? key,
    required this.message,
    required this.isMe,
    required this.onTap,
  }) : super(key: key);

  /// Estrae il testo personalizzato dal messaggio (se presente)
  String _getCustomText() {
    if (message.decryptedContent != null && message.decryptedContent!.contains('|')) {
      final parts = message.decryptedContent!.split('|');
      // Formato: location_share|expiresAt|sessionId|customText
      if (parts.length >= 4 && parts[3].isNotEmpty) {
        return parts[3];
      }
    }
    return 'Posizione'; // Default
  }

  /// Calcola il tempo rimanente prima della scadenza
  String _getTimeRemaining() {
    if (message.decryptedContent != null && message.decryptedContent!.contains('|')) {
      final parts = message.decryptedContent!.split('|');
      if (parts.length >= 2) {
        try {
          final expiresAt = DateTime.parse(parts[1]);
          final now = DateTime.now();

          if (now.isAfter(expiresAt)) {
            return 'Scaduta';
          }

          final diff = expiresAt.difference(now);
          if (diff.inHours > 0) {
            return '${diff.inHours}h';
          } else if (diff.inMinutes > 0) {
            return '${diff.inMinutes}m';
          } else {
            return '< 1m';
          }
        } catch (e) {
          return '';
        }
      }
    }
    return '';
  }

  /// Estrae il sessionId dal messaggio
  String _getSessionId() {
    if (message.decryptedContent != null && message.decryptedContent!.contains('|')) {
      final parts = message.decryptedContent!.split('|');
      if (parts.length >= 3) {
        return parts[2]; // sessionId è il terzo elemento
      }
    }
    return '';
  }

  bool _isExpired() {
    if (message.decryptedContent != null && message.decryptedContent!.contains('|')) {
      final parts = message.decryptedContent!.split('|');
      if (parts.length >= 2) {
        try {
          final expiresAt = DateTime.parse(parts[1]);
          return DateTime.now().isAfter(expiresAt);
        } catch (e) {
          return false;
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final locationService = Provider.of<LocationService>(context);
    final messageSessionId = _getSessionId();
    final isExpired = _isExpired();

    // Verifica se questa è una sessione vecchia (non più attiva)
    final isOldSession = locationService.currentSessionId != null &&
        messageSessionId.isNotEmpty &&
        messageSessionId != locationService.currentSessionId;

    // Verifica se il mittente (isMe) ha fermato la condivisione
    // IMPORTANTE: controlla solo per i MIEI messaggi, non quelli ricevuti!
    final isSharingStoppedByOwner = isMe &&
        messageSessionId.isNotEmpty &&
        locationService.currentSessionId == null &&
        !locationService.isSharingLocation;

    // Verifica se il PARTNER ha fermato (per destinatario che vede messaggio mittente)
    // Se non sto condividendo E il partner location è null o inattiva, consideralo terminato
    final isPartnerStopped = !isMe &&
        messageSessionId.isNotEmpty &&
        (locationService.partnerLocation == null ||
         !locationService.partnerLocation!.isActive ||
         locationService.partnerLocation!.sessionId != messageSessionId);

    // Verifica se la condivisione è stata interrotta tramite action "stop_sharing"
    final hasStopAction = message.action?.type == 'stop_sharing';

    // Condivisione terminata se:
    // - Scaduta
    // - Sessione vecchia (ne è stata aperta una nuova)
    // - Action "stop_sharing" presente
    // - IO (mittente) ho fermato manualmente (solo se isMe)
    // - PARTNER ha fermato (solo se !isMe)
    final isTerminated = isExpired || isOldSession || hasStopAction || isSharingStoppedByOwner || isPartnerStopped;

    // Testo della bubble
    final String statusText = isTerminated
        ? 'Condivisione terminata'
        : 'Condivisione attiva';

    final textColor = isMe ? Colors.white : Colors.black87;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail con gradiente (attivo) o grigio (terminato)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 200,
              height: 100,
              decoration: BoxDecoration(
                gradient: isTerminated
                    ? null // No gradient se terminato
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF3BA8B0),
                          Color(0xFF145A60),
                        ],
                      ),
                color: isTerminated ? Colors.grey.shade400 : null, // Grigio se terminato
              ),
              child: Center(
                child: Icon(
                  Icons.location_on,
                  size: 48,
                  color: isTerminated ? Colors.white70 : Colors.white,
                ),
              ),
            ),
          ),

          // Contenuto sotto (senza bubble - sarà dentro la bubble di _MessageBubble)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Testo stato condivisione
                // Stile identico ai todo: fontSize 15, height 1.4, italic
                Text(
                  statusText,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                    decoration: isTerminated ? TextDecoration.lineThrough : null,
                  ),
                ),

                const SizedBox(height: 6),

                // Countdown con icona orologio (solo se attiva)
                if (!isTerminated)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: isMe ? Colors.white70 : Colors.black54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getTimeRemaining(),
                        style: TextStyle(
                          color: isMe ? Colors.white70 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),

                if (!isTerminated) const SizedBox(height: 6),

                // Orario e spunte
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('HH:mm').format(message.timestamp),
                      style: TextStyle(
                        color: isMe ? Colors.white70 : Colors.black54,
                        fontSize: 11,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        (message.read ?? false) ? Icons.done_all : Icons.done,
                        size: 16,
                        color: (message.read ?? false) ? Colors.lightBlueAccent : Colors.white70,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
