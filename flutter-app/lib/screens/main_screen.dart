import 'package:flutter/material.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../services/pairing_service.dart';
import '../services/couple_selfie_service.dart';
import 'chat_screen.dart';
import 'media_screen.dart';
import 'settings_screen.dart';
import 'couple_selfie_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _isInitialized = false;
  bool _wasPaired = false; // Traccia lo stato precedente per rilevare i cambiamenti

  @override
  void initState() {
    super.initState();
    _initializeTab();

    // Aggiungi listener per rilevare quando il pairing cambia
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pairingService = Provider.of<PairingService>(context, listen: false);
      pairingService.addListener(_onPairingChanged);
    });
  }

  @override
  void dispose() {
    // Rimuovi listener
    final pairingService = Provider.of<PairingService>(context, listen: false);
    pairingService.removeListener(_onPairingChanged);
    super.dispose();
  }

  /// Chiamato quando lo stato del pairing cambia
  void _onPairingChanged() {
    final pairingService = Provider.of<PairingService>(context, listen: false);
    final isPaired = pairingService.isPaired;

    // Se il pairing è appena diventato attivo (da false a true)
    if (isPaired && !_wasPaired) {
      print('🔄 [MAIN_SCREEN] Pairing appena completato, reinizializzo CoupleSelfieService...');

      // Reinizializza il CoupleSelfieService per caricare la foto dal server
      final coupleSelfieService = Provider.of<CoupleSelfieService>(context, listen: false);
      pairingService.getFamilyChatId().then((familyChatId) {
        if (familyChatId != null) {
          coupleSelfieService.initialize(familyChatId);
        }
      });

      // Cambia tab a Chat
      if (mounted) {
        setState(() {
          _selectedIndex = 0;
        });
      }
    }

    // Aggiorna lo stato precedente
    _wasPaired = isPaired;
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
        _wasPaired = pairingService.isPaired; // Inizializza lo stato precedente
      });

      // Se paired, inizializza anche il CoupleSelfieService
      if (pairingService.isPaired) {
        final coupleSelfieService = Provider.of<CoupleSelfieService>(context, listen: false);
        pairingService.getFamilyChatId().then((familyChatId) {
          if (familyChatId != null) {
            coupleSelfieService.initialize(familyChatId);
          }
        });
      }
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
                Color(0xFF3BA8B0),
                Color(0xFF145A60),
              ],
            ),
          ),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                decoration: const BoxDecoration(
                  color: Colors.transparent,
                ),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/logo_white.png',
                        width: 48,
                        height: 48,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'TuyJo',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                leading: const Icon(Icons.chat_bubble, color: Colors.white),
                title: Text(AppLocalizations.of(context)!.navChat, style: const TextStyle(color: Colors.white)),
                selected: _selectedIndex == 0,
                selectedTileColor: Colors.white.withOpacity(0.2),
                onTap: () {
                  _onItemTapped(0);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                leading: const Icon(Icons.perm_media, color: Colors.white),
                title: Text(AppLocalizations.of(context)!.navMedia, style: const TextStyle(color: Colors.white)),
                selected: _selectedIndex == 1,
                selectedTileColor: Colors.white.withOpacity(0.2),
                onTap: () {
                  _onItemTapped(1);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                leading: const Icon(Icons.settings, color: Colors.white),
                title: Text(AppLocalizations.of(context)!.settings, style: const TextStyle(color: Colors.white)),
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
                  icon: const Icon(Icons.menu, color: Color(0xFF3BA8B0)),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ),
          ),
          // Floating couple selfie / pairing status (top right)
          Positioned(
            top: 48,
            right: 16,
            child: Consumer2<PairingService, CoupleSelfieService>(
              builder: (context, pairingService, coupleSelfieService, _) {
                final isPaired = pairingService.isPaired;
                final hasSelfie = coupleSelfieService.hasSelfie;
                final cachedSelfieBytes = coupleSelfieService.cachedSelfieBytes;

                return GestureDetector(
                  onTap: isPaired
                      ? () {
                          // Navigate to couple selfie screen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const CoupleSelfieScreen(),
                            ),
                          );
                        }
                      : null,
                  child: Container(
                    width: 48,
                    height: 48,
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
                    child: ClipOval(
                      // IMPORTANTE: mostra la foto SOLO se paired
                      // Se unpaired, mostra sempre cuore grigio
                      child: isPaired && hasSelfie && cachedSelfieBytes != null
                          ? Image.memory(
                              cachedSelfieBytes,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                // Fallback to teal logo if image fails to load
                                return Image.asset(
                                  'assets/logo_teal.png',
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                );
                              },
                            )
                          : Image.asset(
                              isPaired ? 'assets/logo_teal.png' : 'assets/logo_grey.png',
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
