import 'package:flutter/material.dart';

/// Token di design per TuyJo (post-restyle "Tuijo Chat Polish").
class AppColors {
  AppColors._();

  // Surfaces
  static const Color bgCanvas = Color(0xFFEFE8DC); // beige caldo
  static const Color bgSurface = Colors.white;

  // Brand teal
  static const Color tealLight = Color(0xFF3BA8B0);
  static const Color tealDeep = Color(0xFF145A60);

  // Reply banner accents (versione più chiara del gradiente)
  static const Color tealReplyLight = Color(0xFF4DB8BF);
  static const Color tealReplyDeep = Color(0xFF1D6B72);

  // Testi
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6E6E73);
  static const Color textHintOnSurface = Color(0xFF9AA0A6);

  // Divisori / bordi
  static const Color dividerOnCanvas = Color(0x14000000); // ~8% nero
  static const Color dividerOnGradient = Color(0x33FFFFFF); // ~20% bianco
  static const Color iconCircleOnGradient = Color(0x33FFFFFF); // ~20% bianco

  // Ombre
  static Color shadowSoft = Colors.black.withOpacity(0.06);
  static Color shadowTeal = const Color(0xFF3BA8B0).withOpacity(0.18);

  // Gradients
  static const LinearGradient tealVertical = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [tealLight, tealDeep],
  );

  static const LinearGradient tealDiagonal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [tealLight, tealDeep],
  );
}
