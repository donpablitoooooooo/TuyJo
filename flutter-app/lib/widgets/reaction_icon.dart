import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

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
        color: AppColors.tealDeep,
        border: Border.all(
          color: Colors.white.withOpacity(0.18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        iconData,
        color: Colors.white,
        size: size * 0.5,
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
