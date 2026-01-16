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
      top: -8,
      right: -8,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(4),
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
