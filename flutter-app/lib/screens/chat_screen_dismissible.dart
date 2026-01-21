import 'package:flutter/material.dart';

/// Widget per rendere dismissibile una modale con swipe down
class DismissiblePane extends StatelessWidget {
  final Widget child;
  final VoidCallback onDismissed;

  const DismissiblePane({
    super.key,
    required this.child,
    required this.onDismissed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: (details) {
        // Se lo swipe è verso il basso con velocità sufficiente, chiudi
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          onDismissed();
        }
      },
      child: child,
    );
  }
}
