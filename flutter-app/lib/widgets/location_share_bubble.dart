import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import 'reaction_picker.dart';
import '../services/attachment_service.dart';

/// Widget per il bubble di condivisione posizione
class LocationShareBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final VoidCallback onTap;
  final Function(String reactionType) onReact;
  final AttachmentService? attachmentService;
  final String? currentUserId;
  final String? senderId;

  const LocationShareBubble({
    Key? key,
    required this.message,
    required this.isMe,
    required this.onTap,
    required this.onReact,
    this.attachmentService,
    this.currentUserId,
    this.senderId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Estrai i dati dal messaggio decodificato
    // Formato: "location_share|expiresAt_timestamp"
    String expiresAtText = '';
    if (message.decryptedContent != null && message.decryptedContent!.contains('|')) {
      final parts = message.decryptedContent!.split('|');
      if (parts.length >= 2) {
        try {
          final expiresAt = DateTime.parse(parts[1]);
          final now = DateTime.now();
          final isExpired = now.isAfter(expiresAt);

          if (isExpired) {
            expiresAtText = 'Scaduta';
          } else {
            final diff = expiresAt.difference(now);
            if (diff.inHours > 0) {
              expiresAtText = 'Scade tra ${diff.inHours}h';
            } else {
              expiresAtText = 'Scade tra ${diff.inMinutes}m';
            }
          }
        } catch (e) {
          expiresAtText = '';
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 8, right: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: onTap,
                onLongPress: () {
                  ReactionPicker.show(
                    context,
                    onReactionSelected: onReact,
                    message: message,
                    attachmentService: attachmentService,
                    currentUserId: currentUserId,
                    senderId: senderId,
                  );
                },
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: BoxDecoration(
                    gradient: isMe
                        ? const LinearGradient(
                            colors: [
                              Color(0xFFFF9800), // Orange
                              Color(0xFFF57C00), // Deep orange
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : LinearGradient(
                            colors: [
                              Colors.orange[200]!,
                              Colors.orange[100]!,
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
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icona e titolo
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: isMe ? Colors.white : Colors.orange[800],
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isMe
                                        ? 'Hai condiviso la tua posizione'
                                        : 'Posizione condivisa',
                                    style: TextStyle(
                                      color: isMe ? Colors.white : Colors.orange[900],
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (expiresAtText.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      expiresAtText,
                                      style: TextStyle(
                                        color: isMe
                                            ? Colors.white.withOpacity(0.9)
                                            : Colors.orange[700],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (!isMe) ...[
                          const SizedBox(height: 12),
                          // Call to action
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange[800],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.navigation,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Tocca per visualizzare',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        // Timestamp
                        const SizedBox(height: 8),
                        Text(
                          DateFormat('HH:mm').format(message.timestamp),
                          style: TextStyle(
                            color: isMe
                                ? Colors.white.withOpacity(0.7)
                                : Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Reaction overlay
              if (message.reaction != null)
                Positioned(
                  bottom: -8,
                  right: isMe ? 8 : null,
                  left: !isMe ? 8 : null,
                  child: ReactionOverlay(reaction: message.reaction!),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
