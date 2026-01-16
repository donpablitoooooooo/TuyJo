import 'package:flutter/material.dart';
import '../models/message.dart';

/// Widget che mostra una reaction come badge sovrapposto a una bubble
class ReactionOverlay extends StatelessWidget {
  final Reaction reaction;

  const ReactionOverlay({
    super.key,
    required this.reaction,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: -8,
      right: -8,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Image.asset(
          _getAssetPath(reaction.type),
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  String _getAssetPath(String reactionType) {
    switch (reactionType) {
      case 'love':
        return 'assets/love.png';
      case 'ok':
        return 'assets/ok.png';
      case 'shit':
        return 'assets/shit.png';
      case 'wtf':
        return 'assets/wtf.png';
      case 'done':
        return 'assets/done.png';
      default:
        return 'assets/ok.png'; // Fallback
    }
  }
}
