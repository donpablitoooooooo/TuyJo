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
import 'package:url_launcher/url_launcher.dart';

// Colori (stile modale allegati)
class MediaColors {
  static const Color tealLight = Color(0xFF3BA8B0);
  static const Color tealDark = Color(0xFF145A60);
  // Colori icone come nella modale allegati
  static const Color iconPhoto = Color(0xFF2196F3);    // Blu
  static const Color iconLink = Color(0xFF9C27B0);     // Viola
  static const Color iconDocument = Color(0xFF4CAF50); // Verde
  // Colori mio/tuo
  static const Color mine = Color(0xFF3BA8B0);         // Teal per "mio"
  static const Color theirs = Color(0xFF9E9E9E);       // Grigio per "tuo"
}

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  String? _currentUserId;
  AttachmentService? _attachmentService;
  int _selectedTabIndex = 0; // 0 = Foto, 1 = Link, 2 = Doc

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);

    _attachmentService = AttachmentService(encryptionService: chatService.encryptionService);

    final userId = await pairingService.getMyUserId();
    setState(() {
      _currentUserId = userId;
    });
  }

  /// Ottiene foto e video dai messaggi (più recenti prima)
  List<_MediaItem> _getPhotoItems(List<Message> messages) {
    final List<_MediaItem> items = [];
    for (var message in messages) {
      if (message.attachments != null && message.attachments!.isNotEmpty) {
        for (var attachment in message.attachments!) {
          if (attachment.type == 'photo' || attachment.type == 'video') {
            items.add(_MediaItem(attachment: attachment, message: message));
          }
        }
      }
    }
    // Più recenti prima
    items.sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));
    return items;
  }

  /// Ottiene i link dai messaggi (più recenti prima)
  List<_LinkItem> _getLinkItems(List<Message> messages) {
    final List<_LinkItem> items = [];
    for (var message in messages) {
      if (message.linkUrl != null && message.linkUrl!.isNotEmpty) {
        items.add(_LinkItem(message: message));
      }
    }
    // Più recenti prima
    items.sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));
    return items;
  }

  /// Ottiene i documenti dai messaggi (più recenti prima)
  List<_MediaItem> _getDocumentItems(List<Message> messages) {
    final List<_MediaItem> items = [];
    for (var message in messages) {
      if (message.attachments != null && message.attachments!.isNotEmpty) {
        for (var attachment in message.attachments!) {
          if (attachment.type == 'document') {
            items.add(_MediaItem(attachment: attachment, message: message));
          }
        }
      }
    }
    // Più recenti prima
    items.sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final chatService = Provider.of<ChatService>(context);
    final messages = chatService.messages;

    final photoItems = _getPhotoItems(messages);
    final linkItems = _getLinkItems(messages);
    final documentItems = _getDocumentItems(messages);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Spazio per hamburger/ciliegie
          const SizedBox(height: 100),

          // Tab selector solo icone
          _buildTabSelector(),

          // Content area
          Expanded(
            child: _buildContent(l10n, photoItems, linkItems, documentItems),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 80),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MediaColors.tealLight, MediaColors.tealDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: MediaColors.tealLight.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildTabIcon(0, Icons.photo_library, MediaColors.iconPhoto),
          _buildTabIcon(1, Icons.link_rounded, MediaColors.iconLink),
          _buildTabIcon(2, Icons.description, MediaColors.iconDocument),
        ],
      ),
    );
  }

  Widget _buildTabIcon(int index, IconData icon, Color iconColor) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
          border: isSelected ? null : Border.all(color: Colors.white.withOpacity(0.3)),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          size: 22,
          color: isSelected ? iconColor : Colors.white,
        ),
      ),
    );
  }

  Widget _buildContent(AppLocalizations l10n, List<_MediaItem> photoItems, List<_LinkItem> linkItems, List<_MediaItem> documentItems) {
    switch (_selectedTabIndex) {
      case 0:
        return _PhotoGridView(
          items: photoItems,
          currentUserId: _currentUserId,
          attachmentService: _attachmentService,
        );
      case 1:
        return _LinkListView(
          items: linkItems,
          currentUserId: _currentUserId,
        );
      case 2:
        return _DocumentListView(
          items: documentItems,
          currentUserId: _currentUserId,
          attachmentService: _attachmentService,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Rappresenta un media item (allegato + messaggio)
class _MediaItem {
  final Attachment attachment;
  final Message message;

  _MediaItem({required this.attachment, required this.message});
}

/// Rappresenta un link item
class _LinkItem {
  final Message message;

  _LinkItem({required this.message});
}

// ============================================================================
// DATE SEPARATOR (identico alla chat)
// ============================================================================

class _MonthSeparator extends StatelessWidget {
  final String label;

  const _MonthSeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.grey[300]!,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF3BA8B0),
                    Color(0xFF145A60),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3BA8B0).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.flag_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.grey[300]!,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// VISTA FOTO (GRIGLIA)
// ============================================================================

class _PhotoGridView extends StatelessWidget {
  final List<_MediaItem> items;
  final String? currentUserId;
  final AttachmentService? attachmentService;

  const _PhotoGridView({
    required this.items,
    this.currentUserId,
    this.attachmentService,
  });

  /// Raggruppa gli items per mese/anno (più recenti prima)
  Map<String, List<_MediaItem>> _groupByMonth(List<_MediaItem> items) {
    final Map<String, List<_MediaItem>> grouped = {};
    for (var item in items) {
      final key = DateFormat('MMMM yyyy', 'it').format(item.message.timestamp);
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (items.isEmpty) {
      return _buildEmptyState(l10n.mediaNoPhotos, l10n.mediaNoPhotosDescription, Icons.photo_library_outlined);
    }

    final groupedItems = _groupByMonth(items);
    final months = groupedItems.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
      itemCount: months.length,
      itemBuilder: (context, index) {
        final month = months[index];
        final monthItems = groupedItems[month]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MonthSeparator(label: month),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: monthItems.length,
              itemBuilder: (context, itemIndex) {
                final item = monthItems[itemIndex];
                final isMine = item.message.senderId == currentUserId;
                return _PhotoGridItem(
                  item: item,
                  isVideo: item.attachment.type == 'video',
                  isMine: isMine,
                  currentUserId: currentUserId,
                  attachmentService: attachmentService,
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(String title, String description, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: MediaColors.tealLight.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: MediaColors.tealLight),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: MediaColors.tealDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PhotoGridItem extends StatelessWidget {
  final _MediaItem item;
  final bool isVideo;
  final bool isMine;
  final String? currentUserId;
  final AttachmentService? attachmentService;

  const _PhotoGridItem({
    required this.item,
    required this.isVideo,
    required this.isMine,
    this.currentUserId,
    this.attachmentService,
  });

  @override
  Widget build(BuildContext context) {
    if (attachmentService == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: Icon(Icons.error, color: Colors.grey)),
      );
    }

    final badgeColor = isMine ? MediaColors.mine : MediaColors.theirs;

    return GestureDetector(
      onTap: () {
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: attachmentService!.downloadAndDecryptAttachment(
                item.attachment,
                currentUserId ?? '',
                item.message.senderId,
                useThumbnail: true,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Container(
                    color: Colors.grey[200],
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: badgeColor,
                      ),
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

                return Image.memory(snapshot.data!, fit: BoxFit.cover);
              },
            ),
            if (isVideo)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.4)],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.play_circle_filled, color: Colors.white, size: 36),
                ),
              ),
            // Data badge con colore mio/tuo
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  DateFormat('dd/MM').format(item.message.timestamp),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
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

// ============================================================================
// VISTA LINK (LISTA)
// ============================================================================

class _LinkListView extends StatelessWidget {
  final List<_LinkItem> items;
  final String? currentUserId;

  const _LinkListView({
    required this.items,
    this.currentUserId,
  });

  Map<String, List<_LinkItem>> _groupByMonth(List<_LinkItem> items) {
    final Map<String, List<_LinkItem>> grouped = {};
    for (var item in items) {
      final key = DateFormat('MMMM yyyy', 'it').format(item.message.timestamp);
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (items.isEmpty) {
      return _buildEmptyState(l10n.mediaNoLinks, l10n.mediaNoLinksDescription, Icons.link_off_rounded);
    }

    final groupedItems = _groupByMonth(items);
    final months = groupedItems.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      itemCount: months.length,
      itemBuilder: (context, index) {
        final month = months[index];
        final monthItems = groupedItems[month]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MonthSeparator(label: month),
            ...monthItems.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _LinkListItem(
                item: item,
                isMine: item.message.senderId == currentUserId,
              ),
            )),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(String title, String description, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: MediaColors.tealLight.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: MediaColors.tealLight),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: MediaColors.tealDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LinkListItem extends StatelessWidget {
  final _LinkItem item;
  final bool isMine;

  const _LinkListItem({
    required this.item,
    required this.isMine,
  });

  String _getDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceAll('www.', '');
    } catch (e) {
      return url;
    }
  }

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = item.message.linkUrl ?? '';
    final title = item.message.linkTitle ?? _getDomain(url);
    final description = item.message.linkDescription;
    final domain = _getDomain(url);
    final accentColor = isMine ? MediaColors.mine : MediaColors.theirs;

    return GestureDetector(
      onTap: () => _openLink(context, url),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icona link
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: accentColor.withOpacity(0.3)),
              ),
              child: Icon(Icons.link_rounded, color: accentColor, size: 22),
            ),
            const SizedBox(width: 12),
            // Info link
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.grey[800],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.public, size: 11, color: accentColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          domain,
                          style: TextStyle(fontSize: 11, color: accentColor, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        DateFormat('dd/MM').format(item.message.timestamp),
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: accentColor, size: 20),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// VISTA DOCUMENTI (LISTA)
// ============================================================================

class _DocumentListView extends StatelessWidget {
  final List<_MediaItem> items;
  final String? currentUserId;
  final AttachmentService? attachmentService;

  const _DocumentListView({
    required this.items,
    this.currentUserId,
    this.attachmentService,
  });

  Map<String, List<_MediaItem>> _groupByMonth(List<_MediaItem> items) {
    final Map<String, List<_MediaItem>> grouped = {};
    for (var item in items) {
      final key = DateFormat('MMMM yyyy', 'it').format(item.message.timestamp);
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (items.isEmpty) {
      return _buildEmptyState(l10n.mediaNoDocuments, l10n.mediaNoDocumentsDescription, Icons.description_outlined);
    }

    final groupedItems = _groupByMonth(items);
    final months = groupedItems.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      itemCount: months.length,
      itemBuilder: (context, index) {
        final month = months[index];
        final monthItems = groupedItems[month]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MonthSeparator(label: month),
            ...monthItems.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _DocumentListItem(
                item: item,
                isMine: item.message.senderId == currentUserId,
                currentUserId: currentUserId,
                attachmentService: attachmentService,
              ),
            )),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(String title, String description, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: MediaColors.tealLight.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: MediaColors.tealLight),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: MediaColors.tealDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DocumentListItem extends StatelessWidget {
  final _MediaItem item;
  final bool isMine;
  final String? currentUserId;
  final AttachmentService? attachmentService;

  const _DocumentListItem({
    required this.item,
    required this.isMine,
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
        return const Color(0xFFE53935);
      case 'doc':
      case 'docx':
        return const Color(0xFF1E88E5);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF43A047);
      case 'ppt':
      case 'pptx':
        return const Color(0xFFFF7043);
      default:
        return MediaColors.tealLight;
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
    final accentColor = isMine ? MediaColors.mine : MediaColors.theirs;
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: () {
        if (attachmentService == null) return;

        final isPdf = item.attachment.fileName.toLowerCase().endsWith('.pdf');
        if (isPdf) {
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.mediaDocumentOpenHint),
              backgroundColor: MediaColors.tealLight,
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icona documento
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: fileColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: fileColor.withOpacity(0.3)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.description, color: fileColor, size: 18),
                  Text(
                    fileExtension,
                    style: TextStyle(
                      color: fileColor,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Info documento
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.attachment.fileName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.grey[800],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: fileColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatFileSize(item.attachment.fileSize),
                          style: TextStyle(fontSize: 10, color: fileColor, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.lock_outline, size: 10, color: Colors.grey[500]),
                      const SizedBox(width: 2),
                      Text('E2E', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                      const Spacer(),
                      Text(
                        DateFormat('dd/MM').format(item.message.timestamp),
                        style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: accentColor, size: 20),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// FULLSCREEN IMAGE VIEWER
// ============================================================================

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
            Center(
              child: FutureBuilder<Uint8List?>(
                future: widget.attachmentService.downloadAndDecryptAttachment(
                  widget.attachment,
                  widget.currentUserId ?? '',
                  widget.senderId ?? '',
                  useThumbnail: false,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: MediaColors.tealLight),
                        const SizedBox(height: 16),
                        Text(l10n.mediaLoadingImage, style: const TextStyle(color: Colors.white70)),
                      ],
                    );
                  }

                  if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 64),
                        const SizedBox(height: 16),
                        Text(l10n.mediaImageLoadError, style: const TextStyle(color: Colors.white70)),
                      ],
                    );
                  }

                  return InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                  );
                },
              ),
            ),

            // Close button
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
                        backgroundColor: MediaColors.tealLight.withOpacity(0.7),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom info
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
                        colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.attachment.fileName,
                          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock, color: MediaColors.tealLight, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '${l10n.mediaEncryptedE2E} • ${_formatFileSize(widget.attachment.fileSize)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
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
