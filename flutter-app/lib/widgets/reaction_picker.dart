import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../services/attachment_service.dart';
import 'reaction_icon.dart';

/// Bottom sheet per selezionare una reaction
/// Mostra 4 opzioni: LOVE, OK, SHIT, DONE
class ReactionPicker extends StatelessWidget {
  final Function(String reactionType) onReactionSelected;
  final Message message;
  final AttachmentService? attachmentService;
  final String? currentUserId;
  final String? senderId;

  const ReactionPicker({
    super.key,
    required this.onReactionSelected,
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

              // Reactions grid
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
          Navigator.pop(context);
          onReactionSelected(type);
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

  /// Crea la preview del messaggio (testo + data se todo + thumbnail se foto)
  Widget _buildMessagePreview() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail se c'è una foto
          if (message.attachments != null &&
              message.attachments!.isNotEmpty &&
              attachmentService != null &&
              currentUserId != null &&
              senderId != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildThumbnail(message.attachments!.first),
            ),
          // Testo e data
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
          ),
        ],
      ),
    );
  }

  /// Costruisce la thumbnail decifrata dell'allegato
  Widget _buildThumbnail(Attachment attachment) {
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

  /// Mostra il picker come bottom sheet
  static void show(
    BuildContext context, {
    required Function(String) onReactionSelected,
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
        message: message,
        attachmentService: attachmentService,
        currentUserId: currentUserId,
        senderId: senderId,
      ),
    );
  }
}
