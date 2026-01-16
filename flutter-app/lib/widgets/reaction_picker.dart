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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Reactions grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildReactionButton('love', context),
              _buildReactionButton('ok', context),
              _buildReactionButton('shit', context),
              _buildReactionButton('done', context),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildReactionButton(String type, BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onReactionSelected(type);
      },
      borderRadius: BorderRadius.circular(40),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ReactionIcon(
          type: type,
          size: 56,
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
