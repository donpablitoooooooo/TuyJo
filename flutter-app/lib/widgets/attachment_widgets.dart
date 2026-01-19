import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/attachment.dart';
import '../models/message.dart';

/// Widget per visualizzare immagini allegate
class AttachmentImage extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onTap;

  const AttachmentImage({
    Key? key,
    required this.attachment,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: 200,
            maxHeight: 200,
          ),
          child: attachment.thumbnailData != null
              ? Image.memory(
                  attachment.thumbnailData!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 200,
                      height: 200,
                      color: Colors.grey.shade300,
                      child: const Icon(
                        Icons.broken_image,
                        size: 50,
                        color: Colors.grey,
                      ),
                    );
                  },
                )
              : Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey.shade300,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Widget per visualizzare video allegati
class AttachmentVideo extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onTap;

  const AttachmentVideo({
    Key? key,
    required this.attachment,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Container(
              constraints: const BoxConstraints(
                maxWidth: 200,
                maxHeight: 200,
              ),
              child: attachment.thumbnailData != null
                  ? Image.memory(
                      attachment.thumbnailData!,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 200,
                      height: 200,
                      color: Colors.grey.shade300,
                      child: const Icon(
                        Icons.video_library,
                        size: 50,
                        color: Colors.grey,
                      ),
                    ),
            ),
            // Overlay con icona play
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: const Icon(
                  Icons.play_circle_outline,
                  size: 60,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget per visualizzare file PDF allegati
class AttachmentPdf extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onTap;

  const AttachmentPdf({
    Key? key,
    required this.attachment,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf, color: Colors.red.shade700, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.fileName ?? 'documento.pdf',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PDF',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
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

/// Widget per visualizzare altri file allegati
class AttachmentFile extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onTap;

  const AttachmentFile({
    Key? key,
    required this.attachment,
    required this.onTap,
  }) : super(key: key);

  String _getFileExtension(String? fileName) {
    if (fileName == null || !fileName.contains('.')) return '';
    return fileName.split('.').last.toUpperCase();
  }

  IconData _getFileIcon(String? mimeType) {
    if (mimeType == null) return Icons.insert_drive_file;

    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.startsWith('audio/')) return Icons.audio_file;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('zip') ||
        mimeType.contains('rar') ||
        mimeType.contains('7z')) {
      return Icons.folder_zip;
    }
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description;
    }
    if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) {
      return Icons.table_chart;
    }
    if (mimeType.contains('powerpoint') || mimeType.contains('presentation')) {
      return Icons.slideshow;
    }

    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    final fileExt = _getFileExtension(attachment.fileName);
    final fileIcon = _getFileIcon(attachment.mimeType);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(fileIcon, color: Colors.grey.shade700, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.fileName ?? 'file',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fileExt.isNotEmpty ? fileExt : 'FILE',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
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
    final customText = _getCustomText();
    final timeRemaining = _getTimeRemaining();
    final isExpired = _isExpired();
    final bubbleColor = isMe ? const Color(0xFF3BA8B0) : Colors.grey.shade300;
    final textColor = isMe ? Colors.white : Colors.black87;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail piccola (100px invece di 200px)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 200,
              height: 100, // Metà altezza
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF3BA8B0),
                    const Color(0xFF145A60),
                  ],
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.location_on,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Bubble con testo, countdown e orario
          Container(
            constraints: BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Testo (con strikethrough se scaduto)
                Text(
                  customText,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    decoration: isExpired ? TextDecoration.lineThrough : null,
                  ),
                ),

                const SizedBox(height: 6),

                // Countdown con icona orologio
                if (timeRemaining.isNotEmpty)
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
                        timeRemaining,
                        style: TextStyle(
                          color: isMe ? Colors.white70 : Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 6),

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
                        message.read ? Icons.done_all : Icons.done,
                        size: 16,
                        color: message.read ? Colors.lightBlueAccent : Colors.white70,
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
