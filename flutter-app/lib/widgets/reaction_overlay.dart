import 'package:flutter/material.dart';
import '../models/message.dart';
import 'reaction_icon.dart';

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
      bottom: -10,
      right: -10,
      child: ReactionIcon(
        type: reaction.type,
        size: 48,
      ),
    );
  }
}
