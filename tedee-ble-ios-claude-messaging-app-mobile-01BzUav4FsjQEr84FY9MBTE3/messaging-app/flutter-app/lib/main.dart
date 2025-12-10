import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/pairing_choice_screen.dart';
import 'screens/chat_screen.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/encryption_service.dart';
import 'services/notification_service.dart';
import 'services/pairing_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ChatService()),
        ChangeNotifierProvider(create: (_) => PairingService()),
        Provider(create: (_) => EncryptionService()),
        Provider(create: (_) => NotificationService()),
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
    final pairingService = Provider.of<PairingService>(context);

    if (pairingService.isPaired) {
      return const ChatScreen();
    } else {
      return const PairingChoiceScreen();
    }
  }
}
