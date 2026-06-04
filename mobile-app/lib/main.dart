import 'package:flutter/material.dart';
import 'package:nft_logo_marketplace/features/auth/presentation/splash_screen.dart';
import 'package:nft_logo_marketplace/core/theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nft_logo_marketplace/firebase_options.dart';
import 'package:nft_logo_marketplace/shared/widgets/offline_banner.dart';
import 'package:nft_logo_marketplace/core/services/fcm_service.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await dotenv.load(fileName: ".env");

  // Initialize Firebase FIRST
  await Firebase.initializeApp(
    options: kIsWeb ? DefaultFirebaseOptions.web : null,
  );

  // Enable Firestore Offline Persistence
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Initialize Firebase Cloud Messaging
  if (!kIsWeb) {
    await FCMService.instance.initialize();
  }

  runApp(const NFTLogoMarketplaceApp());
}

class NFTLogoMarketplaceApp extends StatelessWidget {
  const NFTLogoMarketplaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'L E O',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      builder: (context, child) {
        return OfflineBannerWrapper(child: child ?? const SizedBox());
      },
      home: const SplashScreen(),
    );
  }
}
