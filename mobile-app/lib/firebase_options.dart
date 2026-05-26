import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Firebase configuration options for multi-platform support.
/// 
/// Web config is required for Admin Dashboard to connect to Firestore.
/// Android config is auto-detected from google-services.json.
/// 
/// If you need to update the web config:
/// 1. Go to Firebase Console → Project Settings → General
/// 2. Under "Your apps", click "Add app" → Web
/// 3. Copy the config values here
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    // Android uses google-services.json automatically
    // iOS would use GoogleService-Info.plist
    return android;
  }

  /// Web configuration for Admin Dashboard
  /// Uses the same Firebase project as mobile
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBN-6Dq85oDETi3z34xerWUBKudOSrEby8',
    appId: '1:173205078344:web:leo-nft-marketplace-web',
    messagingSenderId: '173205078344',
    projectId: 'leo-nft-marketplace',
    storageBucket: 'leo-nft-marketplace.firebasestorage.app',
    authDomain: 'leo-nft-marketplace.firebaseapp.com',
  );

  /// Android configuration (backup — normally auto-detected from google-services.json)
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBN-6Dq85oDETi3z34xerWUBKudOSrEby8',
    appId: '1:173205078344:android:4d6a87243d1168676eb37d',
    messagingSenderId: '173205078344',
    projectId: 'leo-nft-marketplace',
    storageBucket: 'leo-nft-marketplace.firebasestorage.app',
  );
}
