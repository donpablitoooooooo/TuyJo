import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../models/message.dart';
import '../services/attachment_service.dart';
import 'reaction_icon.dart';
import '../theme/app_colors.dart';

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
          gradient: AppColors.tealVertical,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Maniglia
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header con preview del messaggio
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4, right: 16, bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white, size: 26),
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
                const SizedBox(height: 8),
                Container(
                  margin: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                  height: 1,
                  color: AppColors.dividerOnGradient,
                ),
              ],

              // Actions (testi con effetti logici)
              if (onActionSelected != null) ...[
                if (message.messageType == 'location_share') ...[
                  _buildActionButton(
                    'stop_sharing',
                    AppLocalizations.of(context)!.actionStopSharing,
                    Icons.stop_circle_outlined,
                    context,
                  ),
                ] else ...[
                  // Per tutti i messaggi tranne location_share (inclusi i pending)
                  if (message.messageType == 'todo') ...[
                    _buildActionButton(
                      'complete',
                      AppLocalizations.of(context)!.actionMarkCompleted,
                      Icons.check_circle_outline,
                      context,
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Reply per tutti i messaggi
                  _buildActionButton(
                    'reply',
                    AppLocalizations.of(context)!.actionReply,
                    Icons.reply_outlined,
                    context,
                  ),
                  const SizedBox(height: 8),
                  // Edit solo per i propri messaggi (evita problemi di cifratura)
                  if (message.senderId == currentUserId) ...[
                    _buildActionButton(
                      'edit',
                      AppLocalizations.of(context)!.actionEdit,
                      Icons.edit_outlined,
                      context,
                    ),
                    const SizedBox(height: 8),
                  ],
                  _buildActionButton(
                    'delete',
                    AppLocalizations.of(context)!.actionDelete,
                    Icons.delete_outline,
                    context,
                  ),
                ],
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
        splashColor: Colors.white.withValues(alpha: 0.2),
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
    final bool isDelete = actionType == 'delete';
    final Color foreground = isDelete
        ? const Color(0xFFFFB4A8) // rosa salmone tenue per Delete (matcha lo screenshot)
        : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            FocusScope.of(context).unfocus();
            Navigator.pop(context);
            onActionSelected?.call(actionType);
          },
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withValues(alpha: 0.15),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: foreground, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
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
                      color: Colors.white.withValues(alpha: 0.8),
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
          color: Colors.white.withValues(alpha: 0.2),
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
          color: Colors.white.withValues(alpha: 0.2),
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
                color: Colors.white.withValues(alpha: 0.2),
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
                color: Colors.white.withValues(alpha: 0.2),
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
        color: Colors.white.withValues(alpha: 0.2),
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
