import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nft_logo_marketplace/core/services/firestore_service.dart';

// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    debugPrint("Handling a background message: ${message.messageId}");
  }
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  static FCMService get instance => _instance;

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  FCMService._internal();

  Future<void> initialize() async {
    try {
      // 1. Request permissions for iOS
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (kDebugMode) {
        debugPrint('User granted permission: ${settings.authorizationStatus}');
      }

      // Request Android 13+ explicit notification permissions
      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      // 2. Initialize local notifications for foreground display
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      
      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
      );
      
      await _localNotificationsPlugin.initialize(initializationSettings);

      // Create high importance channel for Android
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_importance_channel', // id
        'High Importance Notifications', // title
        description: 'This channel is used for important notifications.', // description
        importance: Importance.max,
      );

      await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // 3. Set up foreground message handler
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        RemoteNotification? notification = message.notification;
        AndroidNotification? android = message.notification?.android;

        if (notification != null && android != null) {
          _localNotificationsPlugin.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                channel.id,
                channel.name,
                channelDescription: channel.description,
                icon: android.smallIcon ?? '@mipmap/ic_launcher',
              ),
            ),
          );
        }
      });

      // 4. Set up background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // 5. Get initial token
      _fcmToken = await _firebaseMessaging.getToken();
      if (kDebugMode) {
        debugPrint('FCM Token: $_fcmToken');
      }

      // 6. Listen for token refreshes
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        _fcmToken = newToken;
        if (kDebugMode) {
          debugPrint('FCM Token Refreshed: $_fcmToken');
        }
        
        // Auto update if user is logged in
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          await saveTokenToUser(currentUser.uid);
        }
      });

    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM Initialization Error: $e');
      }
    }
  }

  /// Save token to user profile
  Future<void> saveTokenToUser(String walletAddress) async {
    if (_fcmToken != null) {
      String? docId = walletAddress.isNotEmpty ? walletAddress : FirebaseAuth.instance.currentUser?.uid;
      
      if (docId != null && docId.isNotEmpty) {
        await FirestoreService.instance.updateUserFCMToken(docId.toLowerCase(), _fcmToken!);
      }
    }
  }
}
