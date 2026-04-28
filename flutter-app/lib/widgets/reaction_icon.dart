import 'package:flutter/material.dart';

/// Widget per disegnare una reaction custom con stile minimal
/// Tondino teal con icona bianca al centro - stile coordinato con l'app
class ReactionIcon extends StatelessWidget {
  final String type; // 'love', 'ok', 'shit', 'done'
  final double size;

  const ReactionIcon({
    super.key,
    required this.type,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final iconData = _getIconData(type);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF3BA8B0), Color(0xFF145A60)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3BA8B0).withValues(alpha: 0.3),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        iconData,
        color: Colors.white,
        size: size * 0.55,
      ),
    );
  }

  IconData _getIconData(String reactionType) {
    switch (reactionType) {
      case 'love':
        return Icons.favorite;
      case 'ok':
        return Icons.thumb_up;
      case 'shit':
        return Icons.thumb_down;
      case 'done':
        return Icons.check;
      default:
        return Icons.thumb_up;
    }
  }
}
