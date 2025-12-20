import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/chat_service.dart';
import '../services/pairing_service.dart';
import '../services/attachment_service.dart';
import '../models/message.dart';

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _currentUserId;
  AttachmentService? _attachmentService;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Ottiene tutti gli allegati dai messaggi, filtrati per tipo
  List<_MediaItem> _getAttachmentsByType(List<Message> messages, String type) {
    final List<_MediaItem> items = [];

    for (var message in messages) {
      if (message.attachments != null && message.attachments!.isNotEmpty) {
        for (var attachment in message.attachments!) {
          if (attachment.type == type) {
            items.add(_MediaItem(
              attachment: attachment,
              message: message,
            ));
          }
        }
      }
    }

    // Ordina per data più recente
    items.sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final chatService = Provider.of<ChatService>(context);
    final messages = chatService.messages;

    final photos = _getAttachmentsByType(messages, 'photo');
    final videos = _getAttachmentsByType(messages, 'video');
    final documents = _getAttachmentsByType(messages, 'document');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Media'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.photo),
              text: 'Foto (${photos.length})',
            ),
            Tab(
              icon: const Icon(Icons.videocam),
              text: 'Video (${videos.length})',
            ),
            Tab(
              icon: const Icon(Icons.insert_drive_file),
              text: 'Documenti (${documents.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _MediaGrid(items: photos, type: 'photo', currentUserId: _currentUserId, attachmentService: _attachmentService),
          _MediaGrid(items: videos, type: 'video', currentUserId: _currentUserId, attachmentService: _attachmentService),
          _MediaList(items: documents, currentUserId: _currentUserId, attachmentService: _attachmentService),
        ],
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
              type == 'photo' ? 'Nessuna foto' : 'Nessun video',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Le foto e i video condivisi appariranno qui',
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
        // TODO: Apri fullscreen viewer con immagine decifrata
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: attachmentService!.downloadAndDecryptAttachment(
              item.attachment,
              currentUserId ?? '',
              item.message.senderId,
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
              'Nessun documento',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'I documenti condivisi appariranno qui',
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
