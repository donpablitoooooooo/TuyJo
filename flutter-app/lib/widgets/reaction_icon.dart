import 'package:flutter/material.dart';

/// Widget per disegnare una reaction custom con stile minimal e gradient
/// Tondino con colore principale sfumato + icona bianca al centro
class ReactionIcon extends StatelessWidget {
  final String type; // 'love', 'ok', 'shit', 'done'
  final double size;

  const ReactionIcon({
    super.key,
    required this.type,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final iconData = _getIconData(type);
    final gradient = _getGradient(type);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: gradient,
        boxShadow: [
          BoxShadow(
            color: _getBaseColor(type).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        iconData,
        color: Colors.white,
        size: size * 0.55, // Icona al 55% della dimensione del cerchio
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

  Color _getBaseColor(String reactionType) {
    switch (reactionType) {
      case 'love':
        return const Color(0xFFE91E63); // Rosa/magenta
      case 'ok':
        return const Color(0xFF4CAF50); // Verde
      case 'shit':
        return const Color(0xFFFF9800); // Arancione
      case 'done':
        return const Color(0xFF3BA8B0); // Teal (colore principale app)
      default:
        return const Color(0xFF3BA8B0);
    }
  }

  LinearGradient _getGradient(String reactionType) {
    final baseColor = _getBaseColor(reactionType);
    final darkerColor = Color.lerp(baseColor, Colors.black, 0.3)!;

    return LinearGradient(
      colors: [baseColor, darkerColor],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}
