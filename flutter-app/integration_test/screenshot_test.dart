/// Tuijo — Automated Screenshot Capture
///
/// Captures raw screenshots of key app screens for App Store submission.
/// Screenshots are saved to ../screenshots/raw/ and then processed by
/// the Python framing script (screenshots/frame_screenshots.py).
///
/// Usage:
///   # Run on a connected device / simulator:
///   flutter test integration_test/screenshot_test.dart
///
///   # Specify a device (e.g. iPhone 15 Pro Max simulator):
///   flutter test integration_test/screenshot_test.dart -d "iPhone 15 Pro Max"
///
/// Prerequisites:
///   - The app must be logged in and paired (a real or test account).
///   - Some messages / todos should exist so screens are not empty.
///   - For best results, use a 6.7" simulator (iPhone 15 Pro Max).
///
/// Tip: if you prefer manual screenshots, just take them on the simulator
/// and save the PNGs in screenshots/raw/ with the names from config.json:
///   01_chat.png, 02_voice_call.png, 03_location.png,
///   04_todo_calendar.png, 05_pairing.png, 06_media_gallery.png

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:private_messaging/main.dart' as app;

/// Directory where raw screenshots are saved.
final screenshotDir = Directory(
  '${Directory.current.parent.path}/screenshots/raw',
);

Future<void> takeScreenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  // Ensure output directory exists
  if (!screenshotDir.existsSync()) {
    screenshotDir.createSync(recursive: true);
  }

  // Capture screenshot bytes via the binding
  final List<int> bytes = await binding.takeScreenshot(name);

  // Write to file
  final file = File('${screenshotDir.path}/$name.png');
  await file.writeAsBytes(bytes);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Store Screenshots', () {
    testWidgets('01_chat — main chat screen', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // The app should land on the chat screen after login.
      // Wait for messages to load.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await takeScreenshot(binding, '01_chat');
    });

    // ---------------------------------------------------------------
    // The remaining screens require navigation from the chat screen.
    // Uncomment and adjust finders once you have the app running
    // in a state where these screens are reachable.
    // ---------------------------------------------------------------

    // testWidgets('02_voice_call — active call screen', (tester) async {
    //   app.main();
    //   await tester.pumpAndSettle(const Duration(seconds: 3));
    //   // Tap the call button in the app bar
    //   await tester.tap(find.byIcon(Icons.call));
    //   await tester.pumpAndSettle(const Duration(seconds: 2));
    //   await takeScreenshot(binding, '02_voice_call');
    // });

    // testWidgets('03_location — location sharing compass', (tester) async {
    //   app.main();
    //   await tester.pumpAndSettle(const Duration(seconds: 3));
    //   // Navigate to an active location share
    //   await takeScreenshot(binding, '03_location');
    // });

    // testWidgets('04_todo_calendar — todo with calendar', (tester) async {
    //   app.main();
    //   await tester.pumpAndSettle(const Duration(seconds: 3));
    //   // Tap on a TODO message or open calendar
    //   await takeScreenshot(binding, '04_todo_calendar');
    // });

    // testWidgets('05_pairing — QR pairing wizard', (tester) async {
    //   // This requires an unpaired state, harder to automate.
    //   // Recommended: take this screenshot manually.
    //   await takeScreenshot(binding, '05_pairing');
    // });

    // testWidgets('06_media_gallery — media screen', (tester) async {
    //   app.main();
    //   await tester.pumpAndSettle(const Duration(seconds: 3));
    //   // Tap "Media" tab in bottom navigation
    //   await tester.tap(find.text('Media'));
    //   await tester.pumpAndSettle(const Duration(seconds: 2));
    //   await takeScreenshot(binding, '06_media_gallery');
    // });
  });
}
