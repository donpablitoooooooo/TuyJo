import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../services/chat_service.dart';
import '../services/pairing_service.dart';
import '../services/attachment_service.dart';
import '../models/message.dart';
import 'pdf_viewer_screen.dart';

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  String? _currentUserId;
  AttachmentService? _attachmentService;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    // Inizializza AttachmentService con EncryptionService condiviso
    _attachmentService = AttachmentService(encryptionService: chatService.encryptionService);

    final userId = await pairingService.getMyUserId();
    setState(() {
      _currentUserId = userId;
    });
  }

  /// Ottiene tutti gli allegati dai messaggi
  List<_MediaItem> _getAllAttachments(List<Message> messages) {
    final List<_MediaItem> items = [];

    for (var message in messages) {
      if (message.attachments != null && message.attachments!.isNotEmpty) {
        for (var attachment in message.attachments!) {
          items.add(_MediaItem(
            attachment: attachment,
            message: message,
          ));
        }
      }
    }

    // Ordina per data più vecchia (vecchi in alto, nuovi in basso)
    items.sort((a, b) => a.message.timestamp.compareTo(b.message.timestamp));

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chatService = Provider.of<ChatService>(context);
    final messages = chatService.messages;

    final allMedia = _getAllAttachments(messages);

    return Scaffold(
      body: allMedia.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.perm_media_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.mediaNoMedia,
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.mediaNoMediaDescription,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : _AllMediaList(
              items: allMedia,
              currentUserId: _currentUserId,
              attachmentService: _attachmentService,
            ),
    );
  }
}

/// Rappresenta un media item (allegato + messaggio)
class _MediaItem {
  final Attachment attachment;
  final Message message;

  _MediaItem({
    required this.attachment,
    required this.message,
  });
}

/// Lista unificata per tutti i media
class _AllMediaList extends StatefulWidget {
  final List<_MediaItem> items;
  final String? currentUserId;
  final AttachmentService? attachmentService;

  const _AllMediaList({
    required this.items,
    this.currentUserId,
    this.attachmentService,
  });

  @override
  State<_AllMediaList> createState() => _AllMediaListState();
}

class _AllMediaListState extends State<_AllMediaList> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Posiziona lo scroll in basso dopo il primo frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mostra tutti i media (foto, video, documenti) in un'unica griglia
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        final type = item.attachment.type;

        // Renderizza in base al tipo
        if (type == 'photo' || type == 'video') {
          return _MediaGridItem(
            item: item,
            isVideo: type == 'video',
            currentUserId: widget.currentUserId,
            attachmentService: widget.attachmentService,
          );
        } else if (type == 'document') {
          return _DocumentGridItem(
            item: item,
            currentUserId: widget.currentUserId,
            attachmentService: widget.attachmentService,
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

/// Griglia per foto e video (cifrati)
class _MediaGrid extends StatelessWidget {
  final List<_MediaItem> items;
  final String type;
  final String? currentUserId;
  final AttachmentService? attachmentService;

  const _MediaGrid({
    required this.items,
    required this.type,
    this.currentUserId,
    this.attachmentService,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == 'photo' ? Icons.photo_library_outlined : Icons.videocam_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              type == 'photo' ? l10n.mediaNoPhotos : l10n.mediaNoVideos,
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.mediaNoPhotosDescription,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _MediaGridItem(
          item: item,
          isVideo: type == 'video',
          currentUserId: currentUserId,
          attachmentService: attachmentService,
        );
      },
    );
  }
}

/// Singolo elemento della griglia (foto/video cifrato)
class _MediaGridItem extends StatelessWidget {
  final _MediaItem item;
  final bool isVideo;
  final String? currentUserId;
  final AttachmentService? attachmentService;

  const _MediaGridItem({
    required this.item,
    required this.isVideo,
    this.currentUserId,
    this.attachmentService,
  });

  @override
  Widget build(BuildContext context) {
    // Se attachmentService non è disponibile, mostra un placeholder
    if (attachmentService == null) {
      return Container(
        color: Colors.grey[200],
        child: const Center(child: Icon(Icons.error, color: Colors.grey)),
      );
    }

    return GestureDetector(
      onTap: () {
        // Apri fullscreen viewer solo per foto
        if (!isVideo && attachmentService != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => _FullscreenImageViewer(
                attachment: item.attachment,
                attachmentService: attachmentService!,
                currentUserId: currentUserId,
                senderId: item.message.senderId,
              ),
            ),
          );
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: attachmentService!.downloadAndDecryptAttachment(
              item.attachment,
              currentUserId ?? '',
              item.message.senderId,
              useThumbnail: true, // Usa thumbnail per performance nella griglia
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }

              if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                return Container(
                  color: Colors.grey[300],
                  child: const Center(
                    child: Icon(Icons.error, color: Colors.red, size: 24),
                  ),
                );
              }

              return Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
              );
            },
          ),
          if (isVideo)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.3),
                  ],
                ),
              ),
              child: const Align(
                alignment: Alignment.center,
                child: Icon(
                  Icons.play_circle_outline,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
          // Data in basso a destra
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                DateFormat('dd/MM').format(item.message.timestamp),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Singolo elemento della griglia per documenti (cifrato)
class _DocumentGridItem extends StatelessWidget {
  final _MediaItem item;
  final String? currentUserId;
  final AttachmentService? attachmentService;

  const _DocumentGridItem({
    required this.item,
    this.currentUserId,
    this.attachmentService,
  });

  String _getFileExtension(String fileName) {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toUpperCase() : 'FILE';
  }

  Color _getFileColor(String fileName) {
    final ext = _getFileExtension(fileName).toLowerCase();
    switch (ext) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileExtension = _getFileExtension(item.attachment.fileName);
    final fileColor = _getFileColor(item.attachment.fileName);

    return GestureDetector(
      onTap: () {
        if (attachmentService == null) return;

        // Check if it's a PDF - open with integrated viewer
        final isPdf = item.attachment.fileName.toLowerCase().endsWith('.pdf');

        if (isPdf) {
          // Open PDF with integrated viewer
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PdfViewerScreen(
                attachment: item.attachment,
                attachmentService: attachmentService!,
                currentUserId: currentUserId,
                senderId: item.message.senderId,
              ),
            ),
          );
        } else {
          // For non-PDF documents, show a message
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.mediaDocumentOpenHint),
            ),
          );
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background con colore del tipo di file
          Container(
            decoration: BoxDecoration(
              color: fileColor.withOpacity(0.1),
              border: Border.all(color: fileColor.withOpacity(0.3)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.insert_drive_file,
                  color: fileColor,
                  size: 48,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: fileColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    fileExtension,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Data in basso a destra
          Positioned(
            bottom: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                DateFormat('dd/MM').format(item.message.timestamp),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista per documenti (cifrati)
class _MediaList extends StatelessWidget {
  final List<_MediaItem> items;
  final String? currentUserId;
  final AttachmentService? attachmentService;

  const _MediaList({
    required this.items,
    this.currentUserId,
    this.attachmentService,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.mediaNoDocuments,
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.mediaNoDocumentsDescription,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        return _DocumentListItem(
          item: item,
          currentUserId: currentUserId,
          attachmentService: attachmentService,
        );
      },
    );
  }
}

/// Singolo elemento della lista documenti (cifrato)
class _DocumentListItem extends StatelessWidget {
  final _MediaItem item;
  final String? currentUserId;
  final AttachmentService? attachmentService;

  const _DocumentListItem({
    required this.item,
    this.currentUserId,
    this.attachmentService,
  });

  String _getFileExtension(String fileName) {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last.toUpperCase() : 'FILE';
  }

  Color _getFileColor(String fileName) {
    final ext = _getFileExtension(fileName).toLowerCase();
    switch (ext) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileExtension = _getFileExtension(item.attachment.fileName);
    final fileColor = _getFileColor(item.attachment.fileName);

    return InkWell(
      onTap: () {
        // TODO: Apri documento
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            // Icona del file con estensione
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: fileColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.insert_drive_file,
                    color: fileColor,
                    size: 24,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fileExtension,
                    style: TextStyle(
                      color: fileColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Info file
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.attachment.fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _formatFileSize(item.attachment.fileSize),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '•',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('dd/MM/yyyy').format(item.message.timestamp),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Icona download
            Icon(
              Icons.file_download_outlined,
              color: Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget per visualizzare immagine a schermo intero con zoom
class _FullscreenImageViewer extends StatefulWidget {
  final Attachment attachment;
  final AttachmentService attachmentService;
  final String? currentUserId;
  final String? senderId;

  const _FullscreenImageViewer({
    required this.attachment,
    required this.attachmentService,
    this.currentUserId,
    this.senderId,
  });

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
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
                          l10n.mediaLoadingImage,
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
                          l10n.mediaImageLoadError,
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
                              '${l10n.mediaEncryptedE2E} • ${_formatFileSize(widget.attachment.fileSize)}',
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
  }
}
