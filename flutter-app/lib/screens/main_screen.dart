import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/pairing_service.dart';
import 'chat_screen.dart';
import 'media_screen.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeTab();
  }

  Future<void> _initializeTab() async {
    print('⏱️ [MAIN_SCREEN] Starting tab initialization...');
    final startTime = DateTime.now();

    // Aspetta che pairingService sia inizializzato
    final pairingService = Provider.of<PairingService>(context, listen: false);

    print('⏱️ [MAIN_SCREEN] Waiting for pairing service...');
    final pairingStart = DateTime.now();

    // Aspetta l'inizializzazione completa (no timeout - deve completare)
    await pairingService.initialize();

    final pairingDuration = DateTime.now().difference(pairingStart);
    print('⏱️ [MAIN_SCREEN] Pairing service ready in ${pairingDuration.inMilliseconds}ms');
    print('   isPaired: ${pairingService.isPaired}');

    if (mounted) {
      setState(() {
        // Se paired, mostra Chat (index 0), altrimenti Impostazioni (index 2)
        _selectedIndex = pairingService.isPaired ? 0 : 2;
        _isInitialized = true;
      });
    }

    final totalDuration = DateTime.now().difference(startTime);
    print('⏱️ [MAIN_SCREEN] Tab initialization complete in ${totalDuration.inMilliseconds}ms');
    print('   Selected tab: ${_selectedIndex == 0 ? "Chat" : (_selectedIndex == 1 ? "Media" : "Settings")}');
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Mostra loader mentre si inizializza
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final List<Widget> screens = [
      const ChatScreen(),
      const MediaScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      drawer: Drawer(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF667eea),
                Color(0xFF764ba2),
              ],
            ),
          ),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const DrawerHeader(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.favorite, color: Colors.white, size: 48),
                    SizedBox(height: 16),
                    Text(
                      'You & Me',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble, color: Colors.white),
                title: const Text('Chat', style: TextStyle(color: Colors.white)),
                selected: _selectedIndex == 0,
                selectedTileColor: Colors.white.withOpacity(0.2),
                onTap: () {
                  _onItemTapped(0);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.perm_media, color: Colors.white),
                title: const Text('Media', style: TextStyle(color: Colors.white)),
                selected: _selectedIndex == 1,
                selectedTileColor: Colors.white.withOpacity(0.2),
                onTap: () {
                  _onItemTapped(1);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings, color: Colors.white),
                title: const Text('Impostazioni', style: TextStyle(color: Colors.white)),
                selected: _selectedIndex == 2,
                selectedTileColor: Colors.white.withOpacity(0.2),
                onTap: () {
                  _onItemTapped(2);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // Main content
          IndexedStack(
            index: _selectedIndex,
            children: screens,
          ),
          // Floating hamburger menu (top left)
          Positioned(
            top: 48,
            left: 16,
            child: Builder(
              builder: (context) => Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.menu, color: Color(0xFF667eea)),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ),
          ),
          // Floating paired/unpaired status (top right)
          Positioned(
            top: 48,
            right: 16,
            child: Consumer<PairingService>(
              builder: (context, pairingService, _) => Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    pairingService.isPaired ? Icons.link : Icons.link_off,
                    color: pairingService.isPaired ? Colors.green : Colors.red,
                  ),
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
