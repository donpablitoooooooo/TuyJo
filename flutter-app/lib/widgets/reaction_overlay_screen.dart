import 'package:flutter/material.dart';
import 'reaction_picker.dart';

/// Schermata overlay che isola un messaggio e mostra il reaction picker
/// Oscura tutto tranne il messaggio selezionato (stile WhatsApp)
class ReactionOverlayScreen extends StatelessWidget {
  final Rect messageRect;
  final Function(String reactionType) onReactionSelected;

  const ReactionOverlayScreen({
    super.key,
    required this.messageRect,
    required this.onReactionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Overlay scuro con "buco" trasparente sul messaggio
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: CustomPaint(
              painter: _MessageHighlightPainter(messageRect),
              child: Container(),
            ),
          ),

          // Bottom sheet con reactions (allineato in basso)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ReactionPicker(
              onReactionSelected: (type) {
                Navigator.pop(context);
                onReactionSelected(type);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Mostra l'overlay con il messaggio evidenziato
  static void show(
    BuildContext context, {
    required GlobalKey messageKey,
    required Function(String) onReactionSelected,
  }) {
    // Ottieni la posizione e dimensione del messaggio
    final RenderBox? renderBox =
        messageKey.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox == null) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final rect = position & size;

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: ReactionOverlayScreen(
              messageRect: rect,
              onReactionSelected: onReactionSelected,
            ),
          );
        },
      ),
    );
  }
}

/// Custom painter per disegnare l'overlay scuro con un "buco" trasparente
class _MessageHighlightPainter extends CustomPainter {
  final Rect messageRect;

  _MessageHighlightPainter(this.messageRect);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    // Disegna l'overlay scuro su tutto lo schermo
    final screenPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Rimuovi l'area del messaggio (crea un "buco")
    final messagePath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        messageRect,
        const Radius.circular(20),
      ));

    // Combina i path: schermo - messaggio = overlay con buco
    final combinedPath = Path.combine(PathOperation.difference, screenPath, messagePath);

    canvas.drawPath(combinedPath, paint);
  }

  @override
  bool shouldRepaint(_MessageHighlightPainter oldDelegate) {
    return oldDelegate.messageRect != messageRect;
  }
}
