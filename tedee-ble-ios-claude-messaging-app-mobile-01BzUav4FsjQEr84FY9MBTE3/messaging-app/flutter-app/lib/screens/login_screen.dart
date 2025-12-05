import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _privateKeyController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _privateKeyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_usernameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci username')),
      );
      return;
    }

    if (_isLogin && _privateKeyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci la tua chiave privata')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final authService = Provider.of<AuthService>(context, listen: false);

    if (_isLogin) {
      // Login - solo username e chiave privata
      final success = await authService.login(
        _usernameController.text,
        _privateKeyController.text,
      );

      setState(() => _isLoading = false);

      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login fallito o chiave privata invalida')),
        );
      }
    } else {
      // Registrazione - solo username
      final privateKey = await authService.register(
        _usernameController.text,
      );

      setState(() => _isLoading = false);

      if (privateKey != null && mounted) {
        // Mostra la chiave privata all'utente
        _showPrivateKeyDialog(privateKey);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registrazione fallita')),
        );
      }
    }
  }

  void _showPrivateKeyDialog(String privateKey) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ SALVA LA TUA CHIAVE PRIVATA'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Questa è la tua chiave privata. SALVALA in un posto sicuro!',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 16),
              const Text(
                'Senza questa chiave NON potrai decifrare i tuoi messaggi.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.grey[100],
                ),
                child: SelectableText(
                  privateKey,
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Copia negli appunti
              // TODO: Aggiungi package clipboard se necessario
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Chiave copiata! (implementare clipboard)')),
              );
            },
            child: const Text('COPIA'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Effettua logout per forzare il login con chiave
              Provider.of<AuthService>(context, listen: false).logout();
            },
            child: const Text('HO SALVATO LA CHIAVE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 40),
                Text(
                  'Messaggistica Privata',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Solo tu possiedi la chiave dei tuoi messaggi',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                if (_isLogin) ...[
                  TextField(
                    controller: _privateKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Chiave Privata',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.vpn_key),
                      hintText: 'Incolla la tua chiave privata',
                    ),
                    maxLines: 3,
                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : Text(_isLogin ? 'Accedi' : 'Registrati'),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() => _isLogin = !_isLogin);
                  },
                  child: Text(
                    _isLogin
                        ? 'Non hai un account? Registrati'
                        : 'Hai già un account? Accedi',
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
