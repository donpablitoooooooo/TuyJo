import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../services/attachment_service.dart';
import 'reaction_icon.dart';

/// Bottom sheet per selezionare una reaction o azione
/// Reactions (icone): LOVE, OK, SHIT (solo visive)
/// Actions (testo): "Segna come completato" (todo), "Interrompi condivisione" (location)
class ReactionPicker extends StatelessWidget {
  final Function(String reactionType)? onReactionSelected;
  final Function(String actionType)? onActionSelected;
  final Message message;
  final AttachmentService? attachmentService;
  final String? currentUserId;
  final String? senderId;

  const ReactionPicker({
    super.key,
    this.onReactionSelected,
    this.onActionSelected,
    required this.message,
    this.attachmentService,
    this.currentUserId,
    this.senderId,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3BA8B0), Color(0xFF145A60)],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header con preview del messaggio
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 8, right: 16, bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    ),
                    Expanded(
                      child: _buildMessagePreview(),
                    ),
                  ],
                ),
              ),

              // Reactions (icone visive)
              if (onReactionSelected != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildReactionButton('love', context),
                      _buildReactionButton('ok', context),
                      _buildReactionButton('shit', context),
                      _buildReactionButton('done', context),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Actions (testi con effetti logici)
              if (onActionSelected != null) ...[
                if (message.messageType == 'todo') ...[
                  _buildActionButton(
                    'complete',
                    'Segna come completato',
                    Icons.check_circle_outline,
                    context,
                  ),
                  const SizedBox(height: 8),
                  _buildActionButton(
                    'edit',
                    'Modifica',
                    Icons.edit_outlined,
                    context,
                  ),
                  const SizedBox(height: 8),
                  _buildActionButton(
                    'delete',
                    'Elimina',
                    Icons.delete_outline,
                    context,
                  ),
                ],
                if (message.messageType == 'location_share')
                  _buildActionButton(
                    'stop_sharing',
                    'Interrompi condivisione',
                    Icons.stop_circle_outlined,
                    context,
                  ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReactionButton(String type, BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // Rimuovi focus dalla tastiera prima di chiudere (Android)
          FocusScope.of(context).unfocus();
          Navigator.pop(context);
          onReactionSelected?.call(type);
        },
        borderRadius: BorderRadius.circular(40),
        splashColor: Colors.white.withOpacity(0.2),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: ReactionIcon(
            type: type,
            size: 56,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(String actionType, String label, IconData icon, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Material(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            FocusScope.of(context).unfocus();
            Navigator.pop(context);
            onActionSelected?.call(actionType);
          },
          borderRadius: BorderRadius.circular(12),
          splashColor: Colors.white.withOpacity(0.2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Crea la preview del messaggio (testo + data se todo + thumbnail se foto)
  Widget _buildMessagePreview() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thumbnails di tutti gli allegati (orizzontali)
          if (message.attachments != null && message.attachments!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: message.attachments!.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    return _buildAttachmentPreview(message.attachments![index]);
                  },
                ),
              ),
            ),
          // Testo e data
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Prima riga del testo
              if (message.decryptedContent != null && message.decryptedContent!.isNotEmpty)
                Text(
                  message.decryptedContent!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              // Data se è un todo
              if (message.messageType == 'todo' && message.dueDate != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    DateFormat('dd/MM/yyyy').format(message.dueDate!),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Costruisce la preview dell'allegato (thumbnail foto o icona documento)
  Widget _buildAttachmentPreview(Attachment attachment) {
    // Se è un documento, mostra icona file
    if (attachment.type == 'document') {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.insert_drive_file,
          color: Colors.white,
          size: 20,
        ),
      );
    }

    // Se è un video, mostra icona video
    if (attachment.type == 'video') {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(
          Icons.videocam,
          color: Colors.white,
          size: 20,
        ),
      );
    }

    // Se è una foto, mostra thumbnail decifrata
    if (attachment.type == 'photo' &&
        attachmentService != null &&
        currentUserId != null &&
        senderId != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: FutureBuilder<Uint8List?>(
          future: attachmentService!.downloadAndDecryptAttachment(
            attachment,
            currentUserId!,
            senderId!,
            useThumbnail: true,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(
                width: 40,
                height: 40,
                color: Colors.white.withOpacity(0.2),
                child: const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              );
            }

            if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
              return Container(
                width: 40,
                height: 40,
                color: Colors.white.withOpacity(0.2),
                child: const Icon(Icons.image, color: Colors.white, size: 20),
              );
            }

            return Image.memory(
              snapshot.data!,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            );
          },
        ),
      );
    }

    // Fallback: icona generica
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.attach_file,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  /// Mostra il picker come bottom sheet
  static void show(
    BuildContext context, {
    Function(String)? onReactionSelected,
    Function(String)? onActionSelected,
    required Message message,
    AttachmentService? attachmentService,
    String? currentUserId,
    String? senderId,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ReactionPicker(
        onReactionSelected: onReactionSelected,
        onActionSelected: onActionSelected,
        message: message,
        attachmentService: attachmentService,
        currentUserId: currentUserId,
        senderId: senderId,
      ),
    );
  }
}
