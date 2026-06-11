import 'package:flutter/foundation.dart';

/// Stato UI condiviso tra ChatScreen (dove vive la vista calendario) e
/// MainScreen (che disegna hamburger / chiamata / foto profilo sopra la chat).
///
/// Quando la vista calendario è aperta, MainScreen nasconde quei controlli
/// così la X e il "+" della vista calendario possono stare nella zona safe.
final ValueNotifier<bool> calendarViewOpen = ValueNotifier<bool>(false);
