import 'package:flutter/material.dart';
import 'qr_display_screen.dart';
import 'qr_scanner_screen.dart';

/// Schermata che mostra le 2 opzioni per il pairing:
/// 1. Creo io la chiave famiglia (mostra QR)
/// 2. Leggo la chiave famiglia (scansiona QR)
class PairingChoiceScreen extends StatelessWidget {
  const PairingChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurazione Famiglia'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.family_restroom,
              size: 100,
              color: Colors.blue,
            ),
            const SizedBox(height: 40),
            const Text(
              'Benvenuto in Family Chat',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Scegli come configurare il pairing con il tuo partner:',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),

            // Opzione 1: Creo io la chiave
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const QRDisplayScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.qr_code, size: 32),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  'Creo io la chiave famiglia\n(Mostra QR Code)',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),

            const SizedBox(height: 24),

            // Opzione 2: Leggo la chiave
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const QRScannerScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.qr_code_scanner, size: 32),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  'Leggo la chiave famiglia\n(Scansiona QR Code)',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.blue, width: 2),
              ),
            ),

            const SizedBox(height: 40),

            const Text(
              'ℹ️ Su un telefono seleziona "Creo io", sull\'altro "Leggo"',
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
