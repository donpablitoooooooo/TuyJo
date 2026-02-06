import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../services/chat_service.dart';
import '../services/pairing_service.dart';
import '../services/attachment_service.dart';
import '../models/message.dart';
import 'pdf_viewer_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/attachment_widgets.dart';

// Colori (stile modale allegati)
class MediaColors {
  static const Color tealLight = Color(0xFF3BA8B0);
  static const Color tealDark = Color(0xFF145A60);
  // Colori mio/tuo
  static const Color mine = Color(0xFF3BA8B0);         // Teal per "mio"
  static const Color theirs = Color(0xFF9E9E9E);       // Grigio per "tuo"
}

/// Icona share platform-specific (iOS usa ios_share, Android usa share)
IconData get platformShareIcon => Platform.isIOS ? Icons.ios_share : Icons.share;

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
  /// Esclude le preview dei link (fileName inizia con 'link_preview_')
  /// Esclude i messaggi eliminati
  /// Esclude i messaggi che sono link (hanno linkUrl)
  /// Esclude i reminder (hanno allegati duplicati dal TODO originale)
  List<_MediaItem> _getPhotoItems(List<Message> messages) {
    final List<_MediaItem> items = [];
    for (var message in messages) {
      // Salta messaggi eliminati
      if (message.deleted == true) continue;

      // Salta reminder (hanno allegati duplicati dal TODO originale)
      if (message.isReminder == true) continue;

      // Salta messaggi che sono link (gli attachment sono preview del link)
      if (message.linkUrl != null && message.linkUrl!.isNotEmpty) continue;

      if (message.attachments != null && message.attachments!.isNotEmpty) {
        for (var attachment in message.attachments!) {
          if (attachment.type == 'photo' || attachment.type == 'video') {
            // Escludi le preview dei link (doppia sicurezza)
            if (!attachment.fileName.startsWith('link_preview_')) {
              items.add(_MediaItem(attachment: attachment, message: message));
            }
          }
        }
      }
    }
    // Più recenti prima
    items.sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));
    return items;
  }

  /// Ottiene i link dai messaggi (più recenti prima)
  /// Esclude i messaggi eliminati
  List<_LinkItem> _getLinkItems(List<Message> messages) {
    final List<_LinkItem> items = [];
    for (var message in messages) {
      // Salta messaggi eliminati
      if (message.deleted == true) continue;

      if (message.linkUrl != null && message.linkUrl!.isNotEmpty) {
        items.add(_LinkItem(message: message));
      }
    }
    // Più recenti prima
    items.sort((a, b) => b.message.timestamp.compareTo(a.message.timestamp));
    return items;
  }

  /// Ottiene i documenti dai messaggi (più recenti prima)
  /// Esclude i messaggi eliminati
  /// Esclude i reminder (hanno allegati duplicati dal TODO originale)
  List<_MediaItem> _getDocumentItems(List<Message> messages) {
    final List<_MediaItem> items = [];
    for (var message in messages) {
      // Salta messaggi eliminati
      if (message.deleted == true) continue;

      // Salta reminder (hanno allegati duplicati dal TODO originale)
      if (message.isReminder == true) continue;

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

          // Content area (MonthSeparator ha già padding top)
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
          // Stesse icone della modale attach
          _buildTabIcon(0, Icons.photo_library),
          _buildTabIcon(1, Icons.link_rounded),
          _buildTabIcon(2, Icons.insert_drive_file),
        ],
      ),
    );
  }

  Widget _buildTabIcon(int index, IconData icon) {
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
          // Selezionato: teal su bianco, non selezionato: bianco su teal
          color: isSelected ? MediaColors.tealLight : Colors.white,
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
        return _LinkGridView(
          items: linkItems,
          currentUserId: _currentUserId,
          attachmentService: _attachmentService,
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
  Map<String, List<_MediaItem>> _groupByMonth(List<_MediaItem> items, String locale) {
    final Map<String, List<_MediaItem>> grouped = {};
    for (var item in items) {
      final key = DateFormat('MMMM yyyy', locale).format(item.message.timestamp);
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;

    if (items.isEmpty) {
      return _buildEmptyState(l10n.mediaNoPhotos, l10n.mediaNoPhotosDescription, Icons.photo_library_outlined);
    }

    final groupedItems = _groupByMonth(items, locale);
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
              padding: EdgeInsets.zero, // Rimuove padding default della GridView
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
              builder: (context) => FullscreenImageViewer(
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
// VISTA LINK (GRIGLIA MASONRY STILE PINTEREST)
// ============================================================================

class _LinkGridView extends StatelessWidget {
  final List<_LinkItem> items;
  final String? currentUserId;
  final AttachmentService? attachmentService;

  const _LinkGridView({
    required this.items,
    this.currentUserId,
    this.attachmentService,
  });

  Map<String, List<_LinkItem>> _groupByMonth(List<_LinkItem> items, String locale) {
    final Map<String, List<_LinkItem>> grouped = {};
    for (var item in items) {
      final key = DateFormat('MMMM yyyy', locale).format(item.message.timestamp);
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;

    if (items.isEmpty) {
      return _buildEmptyState(l10n.mediaNoLinks, l10n.mediaNoLinksDescription, Icons.link_off_rounded);
    }

    final groupedItems = _groupByMonth(items, locale);
    final months = groupedItems.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 16),
      itemCount: months.length,
      itemBuilder: (context, index) {
        final month = months[index];
        final monthItems = groupedItems[month]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MonthSeparator(label: month),
            // Griglia masonry con 2 colonne
            MasonryGridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              itemCount: monthItems.length,
              itemBuilder: (context, itemIndex) {
                final item = monthItems[itemIndex];
                return _LinkGridItem(
                  item: item,
                  isMine: item.message.senderId == currentUserId,
                  attachmentService: attachmentService,
                  currentUserId: currentUserId,
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

class _LinkGridItem extends StatelessWidget {
  final _LinkItem item;
  final bool isMine;
  final AttachmentService? attachmentService;
  final String? currentUserId;

  const _LinkGridItem({
    required this.item,
    required this.isMine,
    this.attachmentService,
    this.currentUserId,
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

  /// Cerca la thumbnail del link tra gli attachment del messaggio
  Attachment? _findLinkThumbnail() {
    if (item.message.attachments == null) return null;
    for (var attachment in item.message.attachments!) {
      if (attachment.fileName.startsWith('link_preview_') && attachment.type == 'photo') {
        return attachment;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final url = item.message.linkUrl ?? '';
    final title = item.message.linkTitle ?? _getDomain(url);
    final description = item.message.linkDescription;
    final domain = _getDomain(url);
    final accentColor = isMine ? MediaColors.mine : MediaColors.theirs;
    final thumbnail = _findLinkThumbnail();

    return GestureDetector(
      onTap: () => _openLink(context, url),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accentColor.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail (se disponibile)
            if (thumbnail != null && attachmentService != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                child: FutureBuilder<Uint8List?>(
                  future: attachmentService!.downloadAndDecryptAttachment(
                    thumbnail,
                    currentUserId ?? '',
                    item.message.senderId,
                    useThumbnail: true,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        height: 100,
                        color: accentColor.withOpacity(0.1),
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accentColor,
                          ),
                        ),
                      );
                    }

                    if (snapshot.hasData && snapshot.data != null) {
                      return Image.memory(
                        snapshot.data!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      );
                    }

                    // Fallback: icona link se non c'è thumbnail
                    return Container(
                      height: 80,
                      color: accentColor.withOpacity(0.1),
                      child: Center(
                        child: Icon(Icons.link_rounded, color: accentColor, size: 32),
                      ),
                    );
                  },
                ),
              )
            else
              // Nessuna thumbnail: mostra icona link
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                child: Container(
                  height: 60,
                  color: accentColor.withOpacity(0.1),
                  child: Center(
                    child: Icon(Icons.link_rounded, color: accentColor, size: 28),
                  ),
                ),
              ),

            // Contenuto testuale
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titolo
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.grey[800],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Descrizione (se presente)
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 6),

                  // Dominio + data
                  Row(
                    children: [
                      Icon(Icons.public, size: 10, color: accentColor),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          domain,
                          style: TextStyle(fontSize: 10, color: accentColor, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        DateFormat('dd/MM').format(item.message.timestamp),
                        style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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

  Map<String, List<_MediaItem>> _groupByMonth(List<_MediaItem> items, String locale) {
    final Map<String, List<_MediaItem>> grouped = {};
    for (var item in items) {
      final key = DateFormat('MMMM yyyy', locale).format(item.message.timestamp);
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(item);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;

    if (items.isEmpty) {
      return _buildEmptyState(l10n.mediaNoDocuments, l10n.mediaNoDocumentsDescription, Icons.description_outlined);
    }

    final groupedItems = _groupByMonth(items, locale);
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
    final accentColor = isMine ? MediaColors.mine : MediaColors.theirs;

    return GestureDetector(
      onTap: () => _openDocument(context),
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
            // Icona documento - colore verde (mio) o grigio (suo)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accentColor.withOpacity(0.3)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.description, color: accentColor, size: 18),
                  Text(
                    fileExtension,
                    style: TextStyle(
                      color: accentColor,
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
                          color: accentColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatFileSize(item.attachment.fileSize),
                          style: TextStyle(fontSize: 10, color: accentColor, fontWeight: FontWeight.w500),
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
            // Bottone condividi
            GestureDetector(
              onTap: () => _shareDocument(context),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(platformShareIcon, color: accentColor, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareDocument(BuildContext context) async {
    if (attachmentService == null) return;
    final l10n = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            const SizedBox(width: 12),
            Text(l10n.mediaDownloadingDocument),
          ],
        ),
        backgroundColor: MediaColors.tealLight,
        duration: const Duration(seconds: 10),
      ),
    );

    try {
      final bytes = await attachmentService!.downloadAndDecryptAttachment(
        item.attachment,
        currentUserId ?? '',
        item.message.senderId,
      );

      if (bytes == null) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${item.attachment.fileName}');
      await tempFile.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      await SharePlus.instance.share(ShareParams(files: [XFile(tempFile.path)], text: item.attachment.fileName));
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  Future<void> _openDocument(BuildContext context) async {
    if (attachmentService == null) return;

    final isPdf = item.attachment.fileName.toLowerCase().endsWith('.pdf');

    if (isPdf) {
      // PDF: apri con viewer interno
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
      // Altri documenti: scarica e apri con app esterna
      await _downloadAndOpenWithExternalApp(context);
    }
  }

  Future<void> _downloadAndOpenWithExternalApp(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    // Mostra loading
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(l10n.mediaDownloadingDocument),
          ],
        ),
        backgroundColor: MediaColors.tealLight,
        duration: const Duration(seconds: 10),
      ),
    );

    try {
      // Scarica e decripta il file
      final bytes = await attachmentService!.downloadAndDecryptAttachment(
        item.attachment,
        currentUserId ?? '',
        item.message.senderId,
      );

      if (bytes == null) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.mediaDocumentDownloadError),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Salva in file temporaneo
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${item.attachment.fileName}');
      await tempFile.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Apri con app esterna usando open_filex
      final result = await OpenFilex.open(tempFile.path);

      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.mediaNoAppForDocument),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.mediaDocumentOpenError),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// FullscreenImageViewer is now shared from attachment_widgets.dart
