import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/main_screen.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/encryption_service.dart';
import 'services/notification_service.dart';
import 'services/pairing_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Inizializza EncryptionService (carica chiavi RSA se esistono)
  final encryptionService = EncryptionService();
  await encryptionService.generateAndStoreKeyPair();

  // Inizializza PairingService
  final pairingService = PairingService();
  await pairingService.initialize();

  // Inizializza NotificationService
  final notificationService = NotificationService();
  await notificationService.initialize();

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
        ChangeNotifierProvider(create: (_) => ChatService(encryptionService)),
        ChangeNotifierProvider.value(value: pairingService),
        Provider.value(value: encryptionService),
        Provider.value(value: notificationService),
      ],
      child: MaterialApp(
        title: 'Private Messaging',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
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
