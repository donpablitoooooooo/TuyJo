import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge verso Google Block Store (solo Android): salva/recupera un blob nel
/// cloud dell'account Google, ripristinabile sul nuovo dispositivo. Su iOS/altro
/// è no-op (lì si usa iCloud Keychain).
class BlockStoreBridge {
  static const MethodChannel _channel =
      MethodChannel('com.privatemessaging.tuyjo/blockstore');

  static bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  /// Salva [json] nel Block Store (con backup su cloud). True se ok.
  static Future<bool> store(String json) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('store', {'json': json});
      return ok ?? false;
    } catch (e) {
      if (kDebugMode) print('⚠️ [BLOCKSTORE] store failed: $e');
      return false;
    }
  }

  /// Recupera il blob dal Block Store, o null se assente/errore.
  static Future<String?> retrieve() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('retrieve');
    } catch (e) {
      if (kDebugMode) print('⚠️ [BLOCKSTORE] retrieve failed: $e');
      return null;
    }
  }
}
