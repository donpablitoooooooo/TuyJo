import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/main_screen.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/encryption_service.dart';
import 'services/notification_service.dart';
import 'services/pairing_service.dart';
import 'services/message_cache_service.dart';
import 'services/couple_selfie_service.dart';

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
  ));
}

class MyApp extends StatelessWidget {
  final EncryptionService encryptionService;
  final PairingService pairingService;
  final NotificationService notificationService;

  const MyApp({
    super.key,
    required this.encryptionService,
    required this.pairingService,
    required this.notificationService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ChatService(encryptionService, notificationService)),
        ChangeNotifierProvider.value(value: pairingService),
        ChangeNotifierProvider(create: (_) => CoupleSelfieService()),
        Provider.value(value: encryptionService),
        Provider.value(value: notificationService),
      ],
      child: MaterialApp(
        title: 'Private Messaging',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF667eea),
            primary: const Color(0xFF667eea),
            secondary: const Color(0xFF764ba2),
          ),
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF667eea),
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
