import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Script di test per dimostrare che con regole "if true"
/// CHIUNQUE può leggere i messaggi cifrati dal DB
///
/// NOTA: Questo script NON ha le chiavi private RSA!
/// Può solo leggere i messaggi cifrati, non decifrarli.

void main() async {
  print('🔓 Test: Lettura DB senza autenticazione e senza chiavi private\n');

  // Inizializza Firebase con la stessa config dell'app
  // (questa config è PUBBLICA, chiunque può trovarla)
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'YOUR_API_KEY',  // Sostituisci con il tuo
      appId: 'YOUR_APP_ID',
      messagingSenderId: 'YOUR_SENDER_ID',
      projectId: 'YOUR_PROJECT_ID',
    ),
  );

  final firestore = FirebaseFirestore.instance;

  print('📡 Scarico TUTTO il database (tutte le famiglie)...\n');

  try {
    // LEGGI TUTTE LE FAMIGLIE - SENZA AUTENTICAZIONE!
    final familiesSnapshot = await firestore.collection('families').get();

    print('✅ Trovate ${familiesSnapshot.docs.length} famiglie nel DB!\n');
    print('⚠️  Le regole "if true" permettono di scaricare TUTTO!\n');

    int totalMessages = 0;
    int familyCount = 0;

    for (var familyDoc in familiesSnapshot.docs) {
      familyCount++;
      final familyChatId = familyDoc.id;

      print('═══════════════════════════════════════════════════');
      print('FAMIGLIA #$familyCount');
      print('familyChatId: ${familyChatId.substring(0, 30)}...');

      // Leggi i messaggi di questa famiglia
      final messagesSnapshot = await firestore
          .collection('families')
          .doc(familyChatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(3)
          .get();

      print('Messaggi: ${messagesSnapshot.docs.length}');

      for (var msgDoc in messagesSnapshot.docs) {
        totalMessages++;
        final data = msgDoc.data();
        print('  ├─ Messaggio: ${msgDoc.id.substring(0, 10)}...');
        print('  │  Sender: ${data['senderId']?.substring(0, 15)}...');
        print('  │  Timestamp: ${data['timestamp']}');
        print('  │  Encrypted: ${data['encryptedForSender']?.substring(0, 20)}...');
      }

      // Leggi gli users di questa famiglia
      final usersSnapshot = await firestore
          .collection('families')
          .doc(familyChatId)
          .collection('users')
          .get();

      print('Users: ${usersSnapshot.docs.length}');
      for (var userDoc in usersSnapshot.docs) {
        final data = userDoc.data();
        print('  ├─ User: ${userDoc.id.substring(0, 15)}...');
        print('  │  FCM Token: ${data['fcmToken']?.substring(0, 20)}...');
      }

      print('');
    }

    print('═══════════════════════════════════════════════════\n');
    print('📊 STATISTICHE:');
    print('   Famiglie scaricate: $familyCount');
    print('   Messaggi visti: $totalMessages');
    print('');
    print('🔐 CONCLUSIONE:');
    print('   ✅ Posso scaricare TUTTO il database');
    print('   ✅ Vedo tutte le famiglie, users, messaggi cifrati');
    print('   ❌ NON posso decifrare nessun messaggio (no chiavi private)');
    print('   ⚠️  Vedo metadata: timestamp, relazioni, FCM tokens');
    print('   🛡️  La sicurezza dipende SOLO da RSA-2048\n');

  } catch (e) {
    print('❌ Errore: $e');
    print('   (Se permission denied → le regole sono cambiate!)');
  }
}
