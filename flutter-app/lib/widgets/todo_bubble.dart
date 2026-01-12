import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../models/message.dart';
import '../services/attachment_service.dart';
import 'attachment_widgets.dart';

/// Widget riutilizzabile per le bubble TODO
/// Utilizzato sia in chat_screen che in calendar_screen
class TodoMessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool isCompleted;
  final VoidCallback onComplete;
  final String? formattedDate;
  final AttachmentService? attachmentService;
  final String? senderId;
  final String? currentUserId;

  const TodoMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.isCompleted,
    required this.onComplete,
    this.formattedDate,
    this.attachmentService,
    this.senderId,
    this.currentUserId,
  });

  /// Costruisce i widget per mostrare gli allegati (decifrati)
  List<Widget> _buildAttachments() {
    if (message.attachments == null || message.attachments!.isEmpty) {
      if (kDebugMode) {
        print('🔗 [TodoBubble] No attachments for message ${message.id}');
      }
      return [];
    }

    // Se attachmentService non è disponibile, non mostrare allegati
    if (attachmentService == null) {
      if (kDebugMode) {
        print('❌ [TodoBubble] AttachmentService is null for message ${message.id}');
      }
      return [];
    }

    if (kDebugMode) {
      print('✅ [TodoBubble] Building ${message.attachments!.length} attachments');
      print('  - currentUserId: $currentUserId');
      print('  - senderId: $senderId');
    }

    return [
      ...message.attachments!.map((attachment) {
        if (attachment.type == 'photo') {
          return AttachmentImage(
            attachment: attachment,
            isMe: isMe,
            currentUserId: currentUserId,
            senderId: senderId,
            attachmentService: attachmentService!,
          );
        } else if (attachment.type == 'video') {
          return AttachmentVideo(
            attachment: attachment,
            isMe: isMe,
            currentUserId: currentUserId,
            senderId: senderId,
          );
        } else {
          return AttachmentDocument(
            attachment: attachment,
            isMe: isMe,
            currentUserId: currentUserId,
            senderId: senderId,
            attachmentService: attachmentService!,
          );
        }
      }),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bool isPastDue = message.dueDate != null && message.dueDate!.isBefore(DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: isCompleted ? null : onComplete, // Long press per completare
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                gradient: isMe
                    ? const LinearGradient(
                        colors: [
                          Color(0xFF5DBECC), // Purple
                          Color(0xFF3B9DA6), // Deep purple
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [
                          Colors.grey[200]!,
                          Colors.grey[100]!,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isMe
                      ? const Radius.circular(20)
                      : const Radius.circular(4),
                  bottomRight: isMe
                      ? const Radius.circular(4)
                      : const Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isMe
                        ? const Color(0xFF5DBECC).withOpacity(0.3)
                        : Colors.black.withOpacity(0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isMe
                      ? const Radius.circular(20)
                      : const Radius.circular(4),
                  bottomRight: isMe
                      ? const Radius.circular(4)
                      : const Radius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Allegati (se presenti) - senza padding per occupare tutta la larghezza
                    if (message.attachments != null && message.attachments!.isNotEmpty)
                      ..._buildAttachments(),
                    // Testo e altre info con padding
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Testo del todo (mostra "Todo" se vuoto)
                          (message.decryptedContent?.isEmpty ?? true)
                              ? Text(
                                  l10n.chatTodoDefault,
                                  style: TextStyle(
                                    color: isMe ? Colors.white : Colors.black87,
                                    fontSize: 15,
                                    height: 1.4,
                                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              : Linkify(
                                  onOpen: (link) async {
                                    try {
                                      final uri = Uri.parse(link.url);
                                      await launchUrl(
                                        uri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    } catch (e) {
                                      if (kDebugMode) {
                                        print('Errore apertura URL: $e');
                                      }
                                    }
                                  },
                                  text: message.decryptedContent!,
                                  style: TextStyle(
                                    color: isMe ? Colors.white : Colors.black87,
                                    fontSize: 15,
                                    height: 1.4,
                                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                                  ),
                                  linkStyle: TextStyle(
                                    color: isMe ? Colors.white : Colors.blue,
                                    fontSize: 15,
                                    height: 1.4,
                                    decoration: TextDecoration.underline,
                                  ),
                                  options: const LinkifyOptions(
                                    humanize: false,
                                    looseUrl: true,
                                  ),
                                ),

                          // Data e ora (icona campanello per reminder, calendario per evento)
                          if (formattedDate != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  message.isReminder == true
                                      ? Icons.notifications_outlined  // Campanello per reminder
                                      : Icons.calendar_today_outlined, // Calendario per evento
                                  size: 14,
                                  color: isMe
                                      ? Colors.white.withOpacity(0.9)
                                      : Colors.black54,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    formattedDate!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isMe
                                          ? Colors.white.withOpacity(0.9)
                                          : Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // Timestamp del messaggio
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                DateFormat('HH:mm').format(message.timestamp),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isMe
                                      ? Colors.white.withOpacity(0.8)
                                      : Colors.black54,
                                ),
                              ),
                              // Mostra le spunte solo per i messaggi inviati da me
                              if (isMe && !isCompleted) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  (message.read ?? false) ? Icons.done_all : Icons.done,
                                  size: 14,
                                  color: (message.read ?? false)
                                      ? Colors.blue[300]
                                      : Colors.white.withOpacity(0.8),
                                ),
                              ],
                              if (isCompleted) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.check_circle,
                                  size: 12,
                                  color: isMe
                                      ? Colors.white.withOpacity(0.8)
                                      : Colors.green,
                                ),
                              ],
                            ],
                          ),

                          // Hint per long press (solo se non completato)
                          if (!isCompleted) ...[
                            const SizedBox(height: 6),
                            Text(
                              l10n.chatLongPressToComplete,
                              style: TextStyle(
                                fontSize: 10,
                                color: isMe
                                    ? Colors.white.withOpacity(0.6)
                                    : Colors.black38,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
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
