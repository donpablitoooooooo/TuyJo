import 'package:flutter/material.dart';

/// Disegna una reaction: tondino teal con l'icona bianca al centro.
///
/// Le icone sono di Pericon Design (Noun Project), rese "al negativo":
/// sagoma piena bianca e linee teal. Stanno in `assets/reactions/<tipo>.png`.
///
/// Nel messaggio si salva solo il tipo, quindi cambiare un disegno cambia
/// anche le reaction già date. I tipi 'love', 'ok', 'shit' e 'done' esistono
/// dalle versioni precedenti e vanno mantenuti.
class ReactionIcon extends StatelessWidget {
  /// Prima fila del picker, sempre visibile.
  static const List<String> quickTypes = ['love', 'ok', 'pinch', 'scream'];

  /// Dietro il tasto +, al posto delle azioni.
  static const List<String> moreTypes = [
    'no',
    'shit',
    'laugh',
    'done',
    'crossed',
    'flushed',
    'devil',
    'ghost',
    'banana',
    'rocket',
  ];

  static const List<String> allTypes = [...quickTypes, ...moreTypes];

  /// Icona usata per un tipo sconosciuto (es. inviato da una versione più nuova).
  static const String _fallbackType = 'ok';

  final String type;
  final double size;

  const ReactionIcon({
    super.key,
    required this.type,
    this.size = 32,
  });

  static String assetFor(String type) =>
      'assets/reactions/${allTypes.contains(type) ? type : _fallbackType}.png';

  @override
  Widget build(BuildContext context) {
    final glyph = size * 0.64;

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
      alignment: Alignment.center,
      child: Image.asset(
        assetFor(type),
        width: glyph,
        height: glyph,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      ),
    );
  }
}
