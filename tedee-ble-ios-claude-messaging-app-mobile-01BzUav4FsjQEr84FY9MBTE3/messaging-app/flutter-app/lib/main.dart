import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/pairing_choice_screen.dart';
import 'screens/main_screen.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/encryption_service.dart';
import 'services/notification_service.dart';
import 'services/pairing_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final pairingService = Provider.of<PairingService>(context, listen: false);

    // Inizializza i servizi
    await authService.initialize();
    await pairingService.initialize();

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final authService = Provider.of<AuthService>(context);
    final pairingService = Provider.of<PairingService>(context);

    // Se non autenticato → LoginScreen
    if (!authService.isAuthenticated) {
      return const LoginScreen();
    }

    // Se autenticato ma non paired → PairingChoiceScreen
    if (!pairingService.isPaired) {
      return const PairingChoiceScreen();
    }

    // Se autenticato E paired → MainScreen (con menu di navigazione)
    return const MainScreen();
  }
}
