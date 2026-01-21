# Tuijo - Private Messaging & Family Organization App

**Version:** 1.14.0 (Build 19) | **Status:** 🚀 Production Ready

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Firestore-orange)](https://firebase.google.com)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android-lightgrey)](https://flutter.dev)

A secure, end-to-end encrypted messaging and family organization app built with Flutter and Firebase.

---

## 🌟 Key Features

### 💬 Secure Messaging
- **End-to-End Encryption (E2EE)**: All messages encrypted using RSA-2048 + AES-256-GCM
- **Dual Encryption**: Messages encrypted twice (sender + recipient keys) for maximum security
- **Real-time Messaging**: Instant message delivery with read receipts (✓✓)
- **Typing Indicator**: See when your partner is typing
- **Rich Attachments**: Share photos, videos, and documents with E2E encryption

### 📍 Real-Time Location Sharing (NEW!)
- **Live Position Tracking**: Share your real-time GPS location with your partner for 1 or 8 hours
- **Interactive Navigation**: Visual radar interface with directional arrow pointing to partner's position
- **Distance Display**: See exact distance (meters/km) and time since last update
- **Compass Integration**: Arrow rotates based on your device orientation and partner's direction
- **Privacy First**: Location data encrypted and automatically deleted after session expires
- **Session Management**: Stop sharing anytime, partner notified immediately

### 📱 iOS Photo Sharing
- **Native iOS Integration**: Share photos directly from iOS Photos app to Tuijo
- **Method Channel Implementation**: Custom AppDelegate with Flutter Method Channel
- **Seamless File Handling**: Files copied to app's Caches directory and encrypted before upload
- **Universal Sharing**: Works from Photos, Files, and any app with Share Sheet

### ✅ Smart Todo System
- **Date-based Todos**: Create tasks with specific dates or date ranges
- **Smart Reminders**: Automatic notifications 1 hour before due date
- **Calendar View**: Integrated calendar showing all todos with visual markers
- **Long-press Completion**: Quick complete with intuitive gesture
- **Attachments**: Add photos/documents to todos with E2E encryption

### 👥 Family Pairing
- **QR Code Pairing**: Secure device pairing using QR codes
- **Automatic Key Exchange**: Public keys exchanged during pairing for E2E encryption
- **Couple Selfie**: Shared profile photo synced across both devices

### 🔔 Push Notifications
- **Firebase Cloud Messaging**: Reliable push notifications
- **Background Support**: Receive notifications even when app is closed
- **Smart Filtering**: Different notifications for messages, todos, and reminders

### 🌍 Internationalization
- **4 Languages**: English, Spanish, Catalan, Italian
- **Native iOS Localization**: System-level string files

---

## 🚀 What's New in 1.14.0 - Location Sharing & Production Release

### 📍 Real-Time Location Sharing (NEW!)
- **Share Your Position**: Start sharing your real-time GPS location for 1 or 8 hours
- **Live Navigation**: Interactive radar screen with arrow pointing to partner's location
- **Distance & Time**: See exact distance and how recent the partner's position is
- **Compass Support**: Arrow rotates based on device heading and partner's bearing
- **Automatic Expiry**: Location sessions expire automatically, data cleaned up from servers
- **Stop Anytime**: Either partner can stop sharing, other is notified immediately
- **Production Ready**: All test offsets removed, shows real GPS coordinates

### 🌍 Complete Localization
- **All Texts Localized**: Every single UI element now supports all 4 languages (IT, ES, EN, CA)
- **Location UI**: Distance, time indicators, dialog texts - fully translated
- **Message Actions**: Edit, Delete, Stop Sharing - fully localized
- **Time & Alert Pickers**: All labels and alert options in user's language
- **Error Messages**: All user-facing errors now show in user's language
- **41 New Keys**: Added to all .arb files for complete coverage (location, todos, navigation)

### 📝 Message Editing Improvements
- **Edit Pending Messages**: Can now edit messages that are still uploading/failed
- **Delete Pending Messages**: Remove stuck pending messages without errors
- **Smart Handling**: Pending messages are removed locally, normal messages updated in Firestore
- **Attachment Filtering**: Only successfully uploaded attachments shown during edit

### 🎨 UX Improvements
- **Calendar Close Button**: Added X button at top right to close calendar modal
- **Removed Calendar Screen**: Todo calendar now fully integrated into chat
- **Streamlined Navigation**: 3-tab interface (Chat, Media, Settings) instead of 4
- **Cleaner Drawer**: Simplified menu with essential sections only
- **Better UX**: All todo management happens in chat where todos are created

### 🐛 Bug Fixes
- ✅ Removed 1km test offset from location sharing (production ready)
- ✅ Fixed Catalan translations (actionEdit/actionDelete now proper infinitive)
- ✅ Fixed pending message deletion errors (empty attachment URLs)
- ✅ Fixed Firestore NOT_FOUND errors on pending message operations
- ✅ Fixed attachment URL validation before deletion attempts
- ✅ Improved error messages for message updates

### Technical Improvements
- Location service with session management and automatic cleanup
- Compass integration for real-time heading updates
- Localization keys organized and consistent across all languages
- Better pending message state management
- Improved attachment cleanup logic

---

## 📁 Project Structure

```
Tuijo/
├── flutter-app/
│   ├── lib/
│   │   ├── models/          # Data models (Message, Attachment, etc.)
│   │   ├── services/        # Business logic (Chat, Encryption, Pairing)
│   │   ├── screens/         # UI screens (Chat, Settings, Calendar)
│   │   ├── widgets/         # Reusable UI components
│   │   ├── l10n/            # Localization files (4 languages)
│   │   └── main.dart        # App entry point
│   ├── ios/
│   │   └── Runner/
│   │       ├── AppDelegate.swift         # iOS file sharing handler ⭐
│   │       ├── Runner.entitlements       # iOS capabilities
│   │       ├── Base.lproj/               # Storyboard files
│   │       ├── Info.plist                # iOS configuration
│   │       └── GoogleService-Info.plist  # Firebase iOS config
│   ├── android/
│   │   └── app/
│   │       ├── google-services.json      # Firebase Android config
│   │       └── src/main/AndroidManifest.xml
│   └── pubspec.yaml
├── functions/               # Cloud Functions for notifications
└── README.md               # This file
```

---

## 🔧 Setup & Build

### Prerequisites
- Flutter SDK 3.x+
- Xcode 15+ (for iOS)
- Android Studio (for Android)
- Firebase project configured

### Quick Start

```bash
# Clone repository
git clone https://github.com/donpablitoooooooo/Tuijo.git
cd Tuijo/flutter-app

# Install dependencies
flutter pub get

# iOS: Install CocoaPods
cd ios && pod install && cd ..

# Run on device
flutter run --debug
```

### Build for App Store

```bash
# iOS Release Build
flutter build ios --release

# Open Xcode
open ios/Runner.xcworkspace

# In Xcode:
# 1. Select Runner scheme
# 2. Select "Any iOS Device (arm64)"
# 3. Product → Archive
# 4. Distribute App → App Store Connect
```

### Build for Play Store

```bash
# Android Release Build
flutter build appbundle --release

# Output: build/app/outputs/bundle/release/app-release.aab
```

---

## 🔐 Security Architecture

### End-to-End Encryption

**Key Generation**: Each device generates RSA-2048 key pair on first launch

**Pairing**: QR codes exchange public keys only (private keys never leave device)

**Message Encryption**:
1. Generate random AES-256 key
2. Encrypt message with AES-256-GCM
3. Encrypt AES key with recipient's RSA public key → `encrypted_key_recipient`
4. Encrypt AES key with sender's RSA public key → `encrypted_key_sender`
5. Upload to Firebase with both encrypted keys

**Attachment Encryption**:
- Files encrypted with AES-256 before upload
- Encryption key encrypted with RSA for both sender and recipient
- Firebase Storage contains only encrypted binaries

### iOS Security Features
- **Security Scoped Resources**: Proper file access permissions
- **App Groups**: `group.com.privatemessaging.tuyjo`
- **Caches Directory**: Stable file storage until upload completes
- **Automatic Cleanup**: Files deleted after successful upload

---

## 📱 iOS Photo Sharing - Technical Deep Dive

### Flow

```
iOS Photos App
    ↓ (User taps Share → Tuijo)
AppDelegate.application(_:open:options:)
    ↓ (Intercepts file URL)
handleSharedMedia([URL])
    ↓ (Security Scoped Resource access)
copyFileToAppStorage(url)
    ↓ (Copy to Library/Caches/shared_media/)
Method Channel.invokeMethod("onMediaShared")
    ↓ (Send file path to Flutter)
chat_screen.dart._handleSharedFilePaths()
    ↓ (Add to attachments)
User sends message
    ↓ (Encrypt file with AES-256)
Upload to Firebase Storage
    ↓ (Encrypted binary uploaded)
_cleanupAllIOSFiles()
    ↓ (Delete from Caches)
✅ Complete
```

### Configuration

**Info.plist** - Document Types:
```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Images</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.image</string>
            <string>public.jpeg</string>
            <string>public.png</string>
            <string>public.heic</string>
        </array>
    </dict>
</array>
```

**Runner.entitlements**:
```xml
<dict>
    <key>aps-environment</key>
    <string>development</string>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.privatemessaging.tuyjo</string>
    </array>
</dict>
```

**AppDelegate.swift** - Method Channel:
```swift
private let CHANNEL = "com.privatemessaging.tuyjo/shared_media"

// Copy file to Caches directory
let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let tempDir = cachesDir.appendingPathComponent("shared_media", isDirectory: true)

// Send path to Flutter
channel.invokeMethod("onMediaShared", arguments: copiedPaths)
```

**chat_screen.dart** - Method Channel Receiver:
```dart
static const platform = MethodChannel('com.privatemessaging.tuyjo/shared_media');

platform.setMethodCallHandler((call) async {
  if (call.method == 'onMediaShared') {
    final paths = (call.arguments as List).cast<String>();
    await _handleSharedFilePaths(paths);
  }
});
```

---

## 📦 Dependencies

### Core
- `firebase_core: 4.3.0` - Firebase initialization
- `cloud_firestore: 6.1.1` - Realtime database
- `firebase_storage: 13.0.5` - File storage
- `firebase_messaging: 16.1.0` - Push notifications

### Security
- `flutter_secure_storage: 10.0.0` - Secure key storage
- `pointycastle: 3.9.1` - RSA & AES encryption
- `encrypt: 5.0.3` - Encryption utilities

### UI & Utilities
- `provider: 6.1.5` - State management
- `intl: 0.20.2` - Internationalization
- `image_picker: 1.1.2` - Camera & gallery
- `file_picker: 8.1.6` - Document picker
- `qr_flutter: 4.1.0` - QR code generation
- `mobile_scanner: 7.1.4` - QR code scanning
- `image_cropper: 8.0.2` - Circular crop for couple selfie
- `sqflite: 2.3.0` - Local message cache

---

## 🐛 Known Issues & Solutions

### iOS Build Issues

**Problem**: "Cycle inside Runner" error
**Solution**: "Thin Binary" build phase must be LAST (after Resources)

**Problem**: Missing Base.lproj storyboard files
**Solution**: Files created in `ios/Runner/Base.lproj/` (LaunchScreen, Main)

**Problem**: Localization references "en 2", "es 2", etc.
**Solution**: Fixed in project.pbxproj (removed "2" suffix)

### iOS Photo Sharing

**Problem**: File not found during upload
**Solution**: Use Caches directory (not /tmp/), cleanup AFTER upload

**Problem**: Push Notifications capability missing
**Solution**: Added `aps-environment` to Runner.entitlements

---

## ✅ Release Checklist

### Pre-Submission
- [x] iOS photo sharing working (Photos app integration)
- [x] Push notifications configured and tested
- [x] End-to-end encryption verified
- [x] All UI texts localized (en/es/ca/it) - 100% coverage
- [x] App Groups entitlements configured
- [x] Caches directory cleanup verified
- [x] Build cycle dependencies resolved
- [x] Storyboard files present
- [x] TestFlight beta testing completed
- [x] Pending message edit/delete functionality
- [x] Calendar screen removed, integrated into chat
- [x] Version bumped to 1.14.0 (Build 19)

### App Store Connect
**Bundle ID**: `com.privatemessaging.tuyjo`
**App Group**: `group.com.privatemessaging.tuyjo`
**Team ID**: PW2GC2RTH2
**Category**: Lifestyle > Social Networking
**Age Rating**: 4+
**Encryption**: Yes (RSA-2048 + AES-256)

### Required Assets
- [x] App icon (1024x1024)
- [x] iPhone screenshots (6.5", 5.5")
- [x] Privacy policy URL
- [x] Support URL
- [x] Marketing text
- [x] Keywords

---

## 📊 App Store Description

**Title**: Tuijo - Private Couple Messaging

**Subtitle**: Secure E2E encrypted chat & todos

**Description**:
```
Tuijo (Tu y yo - You and I) is a private messaging app designed for couples who value their privacy.

✨ FEATURES
• End-to-end encrypted messages (RSA-2048 + AES-256)
• Real-time location sharing with live navigation
• Share photos directly from iOS Photos app
• Smart todo system with reminders
• Calendar view for family organization
• Real-time message delivery & read receipts
• Typing indicators
• Couple profile photo
• 4 languages: English, Spanish, Catalan, Italian

🔐 SECURITY
• Military-grade encryption
• Keys never leave your device
• No third-party access to your messages
• Secure QR code pairing

📍 LOCATION SHARING
• Share your live GPS position for 1 or 8 hours
• See partner's location with interactive compass
• Real-time distance and direction updates
• Automatic session expiry & cleanup

🎯 PERFECT FOR
• Couples who value privacy
• Long-distance relationships
• Meeting up safely - see when partner is nearby
• Family organization & planning
• Secure photo sharing
• Private todo lists & reminders

Download Tuijo and start your private conversation today.
```

**Keywords**: `private,encrypted,couple,messaging,secure,chat,e2e,privacy,family,todo,reminder,calendar,photos,location,gps,navigation`

---

## 🆘 Support

**Email**: support@tuyjo.com
**GitHub**: [Create an issue](https://github.com/donpablitoooooooo/Tuijo/issues)
**Privacy Policy**: https://tuyjo.com/privacy
**Terms of Service**: https://tuyjo.com/terms

---

## 📄 License

Proprietary - All rights reserved

---

## 🎉 Version History

### 1.14.0 (Build 19) - January 21, 2026 - Production Ready
**NEW**: Real-time location sharing with live navigation and compass
**NEW**: Complete localization - all UI elements in 4 languages (IT, ES, EN, CA)
**NEW**: Edit and delete pending messages (stuck uploads)
**IMPROVED**: Removed separate calendar screen, fully integrated into chat
**IMPROVED**: Streamlined 3-tab navigation (Chat, Media, Settings)
**IMPROVED**: Calendar modal with X close button
**FIXED**: Removed all test offsets from location sharing (production ready)
**FIXED**: Catalan translations for action buttons
**FIXED**: Pending message deletion errors, attachment URL validation

### 1.13.0 (Build 15) - January 15, 2026 - Release Candidate
**NEW**: Native iOS photo sharing from Photos app
**FIXED**: File cleanup timing, build dependencies, localizations
**IMPROVED**: Caches directory usage, project structure cleanup

### 1.12.0 (Build 14) - January 10, 2026
iOS TestFlight release

### 1.12.0 (Build 13) - January 10, 2026
Android Firebase release

---

**Status**: ✅ Production Ready - App Store & Play Store
**Last Updated**: January 21, 2026
**Build**: 1.14.0+19
