import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/main_screen.dart';
import 'screens/voice_call_screen.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/encryption_service.dart';
import 'services/notification_service.dart';
import 'services/pairing_service.dart';
import 'services/message_cache_service.dart';
import 'services/couple_selfie_service.dart';
import 'services/attachment_service.dart';
import 'services/location_service.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('⏱️ [STARTUP] Starting app initialization...');
  final startTime = DateTime.now();

  // Solo Firebase è bloccante - tutto il resto in background
  print('⏱️ [STARTUP] Initializing Firebase...');
  final firebaseStart = DateTime.now();
  await Firebase.initializeApp();
  final firebaseDuration = DateTime.now().difference(firebaseStart);
  print('⏱️ [STARTUP] Firebase initialized in ${firebaseDuration.inMilliseconds}ms');

  // Inizializza servizi (non bloccante - lazy init quando servono)
  final encryptionService = EncryptionService();
  final pairingService = PairingService();
  final notificationService = NotificationService();
  final chatService = ChatService(encryptionService, notificationService);
  final coupleSelfieService = CoupleSelfieService(
    encryptionService: encryptionService,
    pairingService: pairingService,
  );
  final attachmentService = AttachmentService(encryptionService: encryptionService);
  final locationService = LocationService();

  // Configura callback per pulizia cache quando il partner richiede la cancellazione
  pairingService.onPartnerDeletedAll = (String familyChatId) async {
    print('🧹 [MAIN] Partner requested cache deletion, cleaning up...');

    // Pulisci cache messaggi
    chatService.stopListening();
    chatService.clearMessages();

    // Pulisci SOLO cache locale foto (mantieni sul server)
    await coupleSelfieService.removeCoupleSelfie(
      familyChatId,
      deleteFromServer: false,
    );

    print('✅ [MAIN] Cache cleanup completed');
  };

  // Configura callback per chiamate in arrivo (CallKit accept)
  notificationService.onIncomingCall = (String familyChatId, String callerId) {
    print('📞 [MAIN] Call accepted via CallKit from $callerId in family $familyChatId');
    final navigatorState = NotificationService.navigatorKey.currentState;
    if (navigatorState != null) {
      navigatorState.push(
        MaterialPageRoute(
          builder: (context) => const VoiceCallScreen(isOutgoing: false),
        ),
      );
    }
  };

  // Configura callback per rifiuto chiamata (CallKit decline)
  notificationService.onCallDeclined = (String familyChatId, String callerId) {
    print('📞 [MAIN] Call declined via CallKit from $callerId in family $familyChatId');
    // Aggiorna Firestore con status "declined"
    FirebaseFirestore.instance
        .collection('families')
        .doc(familyChatId)
        .collection('calls')
        .doc('current')
        .set({
      'status': 'declined',
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  };

  // Configura callback per fine chiamata (CallKit end)
  notificationService.onCallEnded = (String familyChatId, String callerId) {
    print('📞 [MAIN] Call ended via CallKit from $callerId in family $familyChatId');
    // Pulisci il documento della chiamata su Firestore
    FirebaseFirestore.instance
        .collection('families')
        .doc(familyChatId)
        .collection('calls')
        .doc('current')
        .delete();
  };

  // Inizializza in background (non blocca lo startup)
  encryptionService.generateAndStoreKeyPair(); // No await
  pairingService.initialize(); // No await
  notificationService.initialize(); // No await

  final totalDuration = DateTime.now().difference(startTime);
  print('⏱️ [STARTUP] App ready to launch in ${totalDuration.inMilliseconds}ms');

  runApp(MyApp(
    encryptionService: encryptionService,
    pairingService: pairingService,
    notificationService: notificationService,
    chatService: chatService,
    coupleSelfieService: coupleSelfieService,
    attachmentService: attachmentService,
    locationService: locationService,
  ));
}

class MyApp extends StatelessWidget {
  final EncryptionService encryptionService;
  final PairingService pairingService;
  final NotificationService notificationService;
  final ChatService chatService;
  final CoupleSelfieService coupleSelfieService;
  final AttachmentService attachmentService;
  final LocationService locationService;

  const MyApp({
    super.key,
    required this.encryptionService,
    required this.pairingService,
    required this.notificationService,
    required this.chatService,
    required this.coupleSelfieService,
    required this.attachmentService,
    required this.locationService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider.value(value: chatService),
        ChangeNotifierProvider.value(value: pairingService),
        ChangeNotifierProvider.value(value: coupleSelfieService),
        ChangeNotifierProvider.value(value: locationService),
        Provider.value(value: encryptionService),
        Provider.value(value: notificationService),
        Provider.value(value: attachmentService),
      ],
      child: MaterialApp(
        navigatorKey: NotificationService.navigatorKey,
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en', ''),  // English (default)
          Locale('it', ''),  // Italiano
          Locale('es', ''),  // Español
          Locale('ca', ''),  // Català
        ],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3BA8B0),
            primary: const Color(0xFF3BA8B0),
            secondary: const Color(0xFF145A60),
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF3BA8B0),
            elevation: 0,
          ),
        ),
        home: const AuthWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Ora usiamo sempre MainScreen che gestisce internamente
    // quale tab mostrare (Chat o Impostazioni) in base allo stato del pairing
    return const MainScreen();
  }
}
