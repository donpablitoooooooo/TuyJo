# TuyJo - Private Messaging & Family Organization App

**Version:** 1.1.0 (Build 14) | **Status:** 🚀 Release Candidate - Ready for App Store

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

### 📱 iOS Photo Sharing (NEW!)
- **Native iOS Integration**: Share photos directly from iOS Photos app to TuyJo
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

## 🚀 What's New in 1.1.0 - Release Candidate

### iOS Photo Sharing Implementation

**The Problem**: iOS apps can't directly receive shared photos without proper native integration.

**Our Solution**: Custom AppDelegate + Method Channel architecture:

1. **AppDelegate intercepts share** from iOS Photos app
2. **Security Scoped Resources** used for file access
3. **File copied to Caches directory** (stable, not tmp)
4. **Method Channel sends path to Flutter**
5. **Flutter encrypts and uploads** to Firebase Storage
6. **Cleanup after successful upload**

**Key Files**:
- `ios/Runner/AppDelegate.swift`: Native iOS file handling
- `lib/screens/chat_screen.dart`: Flutter Method Channel receiver
- `ios/Runner/Runner.entitlements`: App Groups + Push Notifications
- `ios/Runner/Info.plist`: Document types + URL schemes

### Bug Fixes
- ✅ Fixed file cleanup timing (after upload, not before)
- ✅ Fixed Xcode build cycle dependencies
- ✅ Fixed localization file references (en/es/ca/it)
- ✅ Added missing Base.lproj storyboard files
- ✅ Restored Push Notifications entitlement
- ✅ Cleaned ShareExtension remnants from project

### Technical Improvements
- Stable Caches directory instead of volatile /tmp/
- Proper build phase ordering in Xcode project
- Validated project.pbxproj structure (balanced braces)
- Removed all orphan project entries

---

## 📁 Project Structure

```
TuyJo/
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
git clone https://github.com/donpablitoooooooo/TuyJo.git
cd TuyJo/flutter-app

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
    ↓ (User taps Share → TuyJo)
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
- [x] All localizations complete (en/es/ca/it)
- [x] App Groups entitlements configured
- [x] Caches directory cleanup verified
- [x] Build cycle dependencies resolved
- [x] Storyboard files present
- [x] TestFlight beta testing completed
- [x] Version bumped to 1.1.0 (Build 14)

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

**Title**: TuyJo - Private Couple Messaging

**Subtitle**: Secure E2E encrypted chat & todos

**Description**:
```
TuyJo (Tu y yo - You and I) is a private messaging app designed for couples who value their privacy.

✨ FEATURES
• End-to-end encrypted messages (RSA-2048 + AES-256)
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

🎯 PERFECT FOR
• Couples who value privacy
• Long-distance relationships
• Family organization & planning
• Secure photo sharing
• Private todo lists & reminders

Download TuyJo and start your private conversation today.
```

**Keywords**: `private,encrypted,couple,messaging,secure,chat,e2e,privacy,family,todo,reminder,calendar,photos`

---

## 🆘 Support

**Email**: support@tuyjo.com
**GitHub**: [Create an issue](https://github.com/donpablitoooooooo/TuyJo/issues)
**Privacy Policy**: https://tuyjo.com/privacy
**Terms of Service**: https://tuyjo.com/terms

---

## 📄 License

Proprietary - All rights reserved

---

## 🎉 Version History

### 1.1.0 (Build 14) - January 15, 2026 - Release Candidate
**NEW**: Native iOS photo sharing from Photos app
**FIXED**: File cleanup timing, build dependencies, localizations
**IMPROVED**: Caches directory usage, project structure cleanup

### 1.0.0 (Build 13) - January 10, 2026
Initial TestFlight release

---

**Status**: ✅ Ready for App Store submission
**Last Updated**: January 15, 2026
**Build**: Release Candidate (1.1.0+14)
