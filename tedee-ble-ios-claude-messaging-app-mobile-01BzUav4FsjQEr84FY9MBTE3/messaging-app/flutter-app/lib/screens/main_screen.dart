import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'chat_screen.dart';
import 'pairing_choice_screen.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/pairing_service.dart';

/// Schermata principale con drawer menu per navigazione
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final pairingService = Provider.of<PairingService>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedIndex == 0 ? 'Family Chat' : 'Configurazione'),
        actions: _selectedIndex == 0
            ? [
                // Indicatore K_family
                IconButton(
                  icon: Icon(
                    pairingService.isPaired ? Icons.lock : Icons.lock_open,
                    color: pairingService.isPaired ? Colors.green : Colors.orange,
                  ),
                  onPressed: () {},
                ),
              ]
            : null,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Colors.blue,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(
                    Icons.family_restroom,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Family Chat',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'User ID: ${authService.currentUser?.id.substring(0, 8)}...',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.message),
              title: const Text('Messaggi'),
              selected: _selectedIndex == 0,
              selectedTileColor: Colors.blue.withOpacity(0.1),
              onTap: () {
                setState(() {
                  _selectedIndex = 0;
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Configurazione'),
              selected: _selectedIndex == 1,
              selectedTileColor: Colors.blue.withOpacity(0.1),
              onTap: () {
                setState(() {
                  _selectedIndex = 1;
                });
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Disconnetti',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () async {
                final chatService = Provider.of<ChatService>(context, listen: false);
                chatService.stopListening();
                await authService.logout();
                // L'AuthWrapper si occuperà di mostrare il LoginScreen
              },
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          ChatScreen(),
          PairingChoiceScreen(),
        ],
      ),
    );
  }
}
