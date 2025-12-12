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

  // Prova a leggere una famiglia specifica
  // (sostituisci con un familyChatId reale dal tuo DB)
  const familyChatId = 'INSERISCI_UN_FAMILY_CHAT_ID_REALE';

  print('📡 Tentativo di lettura famiglia: ${familyChatId.substring(0, 10)}...\n');

  try {
    // Leggi messaggi - SENZA AUTENTICAZIONE!
    final messagesSnapshot = await firestore
        .collection('families')
        .doc(familyChatId)
        .collection('messages')
        .limit(5)
        .get();

    print('✅ Riuscito a leggere ${messagesSnapshot.docs.length} messaggi!\n');
    print('⚠️  Le regole "if true" permettono a CHIUNQUE di leggere!\n');

    for (var doc in messagesSnapshot.docs) {
      final data = doc.data();
      print('─────────────────────────────────────');
      print('Messaggio ID: ${doc.id}');
      print('Sender: ${data['senderId']?.substring(0, 20)}...');
      print('Timestamp: ${data['timestamp']}');
      print('encryptedForSender: ${data['encryptedForSender']?.substring(0, 30)}...');
      print('encryptedForRecipient: ${data['encryptedForRecipient']?.substring(0, 30)}...');
      print('');
    }

    print('─────────────────────────────────────\n');
    print('🔐 CONCLUSIONE:');
    print('   ✅ Posso leggere i messaggi cifrati');
    print('   ❌ NON posso decifrarli (no chiavi private)');
    print('   ⚠️  Vedo metadata: timestamp, relazioni, senderId');
    print('   🛡️  La sicurezza dipende SOLO da RSA-2048\n');

  } catch (e) {
    print('❌ Errore: $e');
    print('   (Se permission denied → le regole sono cambiate!)');
  }
}
