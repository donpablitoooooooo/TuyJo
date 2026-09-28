import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage sicuro unico dell'app (Keychain su iOS, Keystore su Android).
///
/// iOS: le query NON filtrano sull'accessibilità del Keychain
/// (`accessibility: null`). Il default del plugin è `unlocked`
/// (kSecAttrAccessibleWhenUnlocked) e viene messo anche nelle letture come
/// filtro: così una voce resa leggibile "dopo il primo sblocco" non verrebbe
/// più trovata.
///
/// L'accessibilità delle voci la decide l'AppDelegate
/// (`migrateKeychainAccessibility`), che le porta tutte ad
/// AfterFirstUnlock: una chiamata accettata a iPhone bloccato deve poter
/// leggere chiavi e identificativi della coppia. Le voci nuove nascono con il
/// default di sistema (WhenUnlocked) e vengono migrate al primo passaggio
/// successivo in/da foreground; gli aggiornamenti conservano l'accessibilità
/// già impostata.
const FlutterSecureStorage appSecureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(accessibility: null),
);
