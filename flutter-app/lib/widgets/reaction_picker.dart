import 'package:flutter/material.dart';
import 'reaction_icon.dart';

/// Bottom sheet per selezionare una reaction
/// Mostra 4 opzioni: LOVE, OK, SHIT, DONE
class ReactionPicker extends StatelessWidget {
  final Function(String reactionType) onReactionSelected;

  const ReactionPicker({
    super.key,
    required this.onReactionSelected,
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
              // Header con X
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 8, bottom: 16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
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
            size: 52,
          ),
        ),
      ),
    );
  }

  /// Mostra il picker come bottom sheet
  static void show(
    BuildContext context, {
    required Function(String) onReactionSelected,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ReactionPicker(
        onReactionSelected: onReactionSelected,
      ),
    );
  }
}
