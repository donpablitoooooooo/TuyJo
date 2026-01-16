import 'package:flutter/material.dart';

/// Bottom sheet per selezionare una reaction
/// Mostra 5 opzioni: LOVE, OK, SHIT, WTF, DONE
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
              _buildReactionButton('love', 'assets/love.png', context),
              _buildReactionButton('ok', 'assets/ok.png', context),
              _buildReactionButton('shit', 'assets/shit.png', context),
              _buildReactionButton('wtf', 'assets/wtf.png', context),
              _buildReactionButton('done', 'assets/done.png', context),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildReactionButton(String type, String assetPath, BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onReactionSelected(type);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 64,
        height: 64,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
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
