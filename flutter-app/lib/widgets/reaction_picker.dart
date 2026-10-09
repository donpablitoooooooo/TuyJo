import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../models/message.dart';
import '../services/attachment_service.dart';
import 'reaction_icon.dart';

/// Bottom sheet per selezionare una reaction o azione.
/// Reactions: prima fila sempre visibile (cuore, ok, ma che vuoi, urlo) più il
/// tasto +, che mostra le altre icone al posto delle azioni. La modale resta
/// della stessa altezza.
/// Actions (testo): Rispondi, Modifica, Elimina, "Segna come completato" (todo),
/// "Interrompi condivisione" (location).
class ReactionPicker extends StatefulWidget {
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

  /// Icone per riga, uguale per la prima fila (4 + tasto +) e per la griglia.
  static const int _perRow = 5;

  @override
  State<ReactionPicker> createState() => _ReactionPickerState();

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

class _ReactionPickerState extends State<ReactionPicker> {
  static const double _maxDiameter = 56;

  bool _showMore = false;

  /// Miniature già richieste: il tasto + ridisegna il picker e non deve
  /// riscaricare e ridecifrare le foto.
  final Map<String, Future<Uint8List?>> _thumbnails = {};

  Message get message => widget.message;

  @override
  Widget build(BuildContext context) {
    final hasReactions = widget.onReactionSelected != null;
    final hasActions = widget.onActionSelected != null;

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

              // Prima fila: 4 reactions + tasto +
              if (hasReactions) ...[
                _buildReactionRow([
                  for (final type in ReactionIcon.quickTypes) (d) => _buildReactionButton(type, d, context),
                  _buildMoreButton,
                ]),
                const SizedBox(height: 16),
              ],

              // Azioni oppure, dopo il +, le altre reactions nello stesso spazio.
              // IndexedStack prende l'altezza del figlio più alto, così la
              // modale non cambia dimensione quando si preme +.
              if (hasActions)
                IndexedStack(
                  index: hasReactions && _showMore ? 1 : 0,
                  alignment: Alignment.topCenter,
                  children: [
                    _buildActions(context),
                    if (hasReactions) _buildMoreGrid(context) else const SizedBox.shrink(),
                  ],
                )
              else if (hasReactions && _showMore)
                _buildMoreGrid(context),
            ],
          ),
        ),
      ),
    );
  }

  /// Riga di 5 posti uguali: le icone restano in colonna tra prima fila e
  /// griglia. Il diametro è 56 se c'è spazio, altrimenti si adatta allo schermo.
  Widget _buildReactionRow(List<Widget Function(double diameter)> cells) {
    const perRow = ReactionPicker._perRow;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final diameter = math.min(_maxDiameter, constraints.maxWidth / perRow - 8);
          return Row(
            children: [
              for (var i = 0; i < perRow; i++)
                Expanded(
                  child: Center(
                    child: i < cells.length ? cells[i](diameter) : const SizedBox.shrink(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMoreGrid(BuildContext context) {
    const types = ReactionIcon.moreTypes;
    const perRow = ReactionPicker._perRow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var start = 0; start < types.length; start += perRow)
          _buildReactionRow([
            for (final type in types.skip(start).take(perRow)) (d) => _buildReactionButton(type, d, context),
          ]),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
          if (message.senderId == widget.currentUserId) ...[
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
    );
  }

  Widget _buildReactionButton(String type, double diameter, BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // Rimuovi focus dalla tastiera prima di chiudere (Android)
          FocusScope.of(context).unfocus();
          Navigator.pop(context);
          widget.onReactionSelected?.call(type);
        },
        customBorder: const CircleBorder(),
        splashColor: Colors.white.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: ReactionIcon(
            type: type,
            size: diameter,
          ),
        ),
      ),
    );
  }

  /// Tasto + (diventa una freccia su quando la griglia è aperta)
  Widget _buildMoreButton(double diameter) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _showMore = !_showMore),
        customBorder: const CircleBorder(),
        splashColor: Colors.white.withValues(alpha: 0.2),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.5),
            ),
            child: Icon(
              _showMore ? Icons.keyboard_arrow_up : Icons.add,
              color: Colors.white,
              size: diameter * 0.55,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(String actionType, String label, IconData icon, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Material(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            FocusScope.of(context).unfocus();
            Navigator.pop(context);
            widget.onActionSelected?.call(actionType);
          },
          borderRadius: BorderRadius.circular(12),
          splashColor: Colors.white.withValues(alpha: 0.2),
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
        widget.attachmentService != null &&
        widget.currentUserId != null &&
        widget.senderId != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: FutureBuilder<Uint8List?>(
          future: _thumbnails.putIfAbsent(
            attachment.id,
            () => widget.attachmentService!.downloadAndDecryptAttachment(
              attachment,
              widget.currentUserId!,
              widget.senderId!,
              useThumbnail: true,
            ),
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
}
