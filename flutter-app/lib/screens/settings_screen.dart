import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/pairing_service.dart';
import '../services/encryption_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import 'pairing_wizard_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = const FlutterSecureStorage();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _copyPrivateKey() async {
    setState(() => _isLoading = true);
    try {
      final privateKey = await _storage.read(key: 'rsa_private_key');

      if (privateKey == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Nessuna chiave privata trovata')),
              ],
            ),
            backgroundColor: Colors.orange[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        return;
      }

      await Clipboard.setData(ClipboardData(text: privateKey));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Chiave privata copiata!')),
            ],
          ),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Errore: $e')),
            ],
          ),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePairing(bool deleteMessages) async {
    setState(() => _isLoading = true);
    try {
      final pairingService = Provider.of<PairingService>(context, listen: false);
      final chatService = Provider.of<ChatService>(context, listen: false);

      final chatId = await pairingService.getFamilyChatId();
      final myUserId = await pairingService.getMyUserId();

      // Prima fai unpair (rimuove il documento users e notifica il partner)
      await pairingService.clearPairing();

      // Poi eventualmente elimina messaggi e foto
      if (deleteMessages && chatId != null && mounted) {
        // Elimina messaggi + foto di coppia
        await chatService.deleteMessagesAndCoupleSelfie(chatId);

        // Pulisci anche la cache locale della foto
        final coupleSelfieService = Provider.of<CoupleSelfieService>(context, listen: false);
        await coupleSelfieService.removeCoupleSelfie(chatId);
      } else if (!deleteMessages && chatId != null && myUserId != null && mounted) {
        // Solo unpair: rimuovi solo il token FCM
        final notificationService = Provider.of<NotificationService>(context, listen: false);
        await notificationService.deleteTokenFromFirestore(chatId, myUserId);
      }
      chatService.stopListening();
      chatService.clearMessages();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(deleteMessages ? 'Tutto eliminato' : 'Pairing eliminato'),
              ),
            ],
          ),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Errore: $e')),
            ],
          ),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showNewPairingDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.favorite, color: Color(0xFF667eea)),
            SizedBox(width: 12),
            Text('Nuovo Pairing'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Stai per creare un nuovo pairing.',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 16),
            Text(
              '💡 Consiglio: salva la chiave privata prima di procedere, così potrai recuperare l\'account in caso di perdita del dispositivo.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Mostra dialog per salvare la chiave (opzionale)
              _showSaveKeyDialog();
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF667eea)),
            child: const Text('Continua'),
          ),
        ],
      ),
    );
  }

  void _showSaveKeyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.backup, color: Color(0xFF667eea)),
            SizedBox(width: 12),
            Text('Salva Chiave'),
          ],
        ),
        content: const Text(
          'Vuoi salvare ora la tua chiave privata?\n\nPotrai farlo anche dopo dal menu Backup.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Vai direttamente al wizard
              _startPairingWizard();
            },
            child: const Text('Più tardi'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Copia la chiave e poi vai al wizard
              await _copyPrivateKey();
              _startPairingWizard();
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF667eea)),
            child: const Text('Salva ora'),
          ),
        ],
      ),
    );
  }

  void _showRestoreDialog() {
    final keyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.restore, color: Color(0xFF667eea)),
            SizedBox(width: 12),
            Text('Ripristino'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Incolla qui la tua chiave privata:'),
            const SizedBox(height: 16),
            TextField(
              controller: keyController,
              decoration: InputDecoration(
                hintText: 'Chiave privata...',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF667eea), width: 2),
                ),
              ),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              keyController.dispose();
              Navigator.pop(context);
            },
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () async {
              final key = keyController.text.trim();
              keyController.dispose();
              Navigator.pop(context);

              if (key.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(child: Text('Chiave privata vuota')),
                      ],
                    ),
                    backgroundColor: Colors.orange[700],
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
                return;
              }

              // Ripristina la chiave
              setState(() => _isLoading = true);
              try {
                final encryptionService = Provider.of<EncryptionService>(context, listen: false);
                final pairingService = Provider.of<PairingService>(context, listen: false);

                encryptionService.loadPrivateKey(key);
                final publicKey = await encryptionService.deriveAndSavePublicKey();

                if (publicKey == null) {
                  throw Exception('Impossibile derivare la chiave pubblica');
                }

                await _storage.write(key: 'rsa_private_key', value: key);
                await pairingService.saveMyPublicKey(publicKey);

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 12),
                        Expanded(child: Text('Chiave ripristinata! Ora fai il pairing.')),
                      ],
                    ),
                    backgroundColor: Colors.green[600],
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );

                // Vai al wizard di pairing
                await Future.delayed(const Duration(seconds: 1));
                _startPairingWizard();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.error, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(child: Text('Errore: $e')),
                      ],
                    ),
                    backgroundColor: Colors.red[600],
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              } finally {
                setState(() => _isLoading = false);
              }
            },
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF667eea)),
            child: const Text('Ripristina'),
          ),
        ],
      ),
    );
  }

  Future<void> _startPairingWizard() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PairingWizardScreen(),
      ),
    );
    _checkPairingStatus();
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber, color: Colors.red),
            SizedBox(width: 12),
            Text('Reset Pairing'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Scegli come resettare:'),
            SizedBox(height: 20),
            _DeleteOption(
              icon: Icons.link_off,
              title: 'Solo Pairing',
              description: 'I messaggi restano (ma illeggibili)',
            ),
            SizedBox(height: 12),
            _DeleteOption(
              icon: Icons.delete_forever,
              title: 'Pairing e Messaggi',
              description: 'Elimina tutto (irreversibile)',
              isDestructive: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePairing(false);
            },
            child: const Text('Solo Pairing'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deletePairing(true);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Tutto'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Leggi lo stato pairing dal PairingService (con listen: true per auto-aggiornamento)
    final pairingService = Provider.of<PairingService>(context);
    final isPaired = pairingService.isPaired;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
      children: [
        // Header
        Center(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.settings, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),
              const Text(
                'Impostazioni',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF667eea),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),

        // Pairing Section
        _SettingsSection(
          title: 'Pairing',
          icon: Icons.favorite,
          iconColor: const Color(0xFF667eea),
          children: [
            if (isPaired) ...[
              // Paired: mostra status e backup
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[600]),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Dispositivi accoppiati ❤️',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Salva la tua chiave privata se non l\'hai fatto',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 12),
              _OutlineButton(
                onPressed: _copyPrivateKey,
                icon: Icons.backup,
                label: 'Backup Chiave',
              ),
            ] else ...[
              // Unpaired: mostra scelta Nuovo vs Ripristino
              const Text(
                'Scegli come procedere:',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              _PurpleButton(
                onPressed: _showNewPairingDialog,
                icon: Icons.favorite,
                label: 'Nuovo Pairing',
              ),
              const SizedBox(height: 12),
              _OutlineButton(
                onPressed: _showRestoreDialog,
                icon: Icons.restore,
                label: 'Ripristino da Backup',
              ),
            ],
          ],
        ),

        // Delete Section (only if paired)
        if (isPaired) ...[
          const SizedBox(height: 24),
          _SettingsSection(
            title: 'Zona Pericolosa',
            icon: Icons.warning,
            iconColor: Colors.red,
            children: [
              const Text(
                'Elimina il pairing con il dispositivo accoppiato',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 16),
              _OutlineButton(
                onPressed: _showDeleteDialog,
                icon: Icons.delete_outline,
                label: 'Reset Pairing',
                color: Colors.red,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// Custom widgets per il design
class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.icon,
    this.iconColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor ?? const Color(0xFF667eea), size: 24),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

class _PurpleButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  const _PurpleButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color? color;

  const _OutlineButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final buttonColor = color ?? const Color(0xFF667eea);

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: buttonColor, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: buttonColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: buttonColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isDestructive;

  const _DeleteOption({
    required this.icon,
    required this.title,
    required this.description,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: isDestructive ? Colors.red : Colors.grey[600],
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDestructive ? Colors.red : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 12,
                  color: isDestructive ? Colors.red[300] : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
