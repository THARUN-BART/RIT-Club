import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// Define navigator key - make sure to use this in your MaterialApp
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class PushNotifications {
  static final FirebaseMessaging _firebaseMessaging =
      FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin
  _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Check if user is logged in directly using Firebase Auth
  static bool isUserLoggedIn() {
    return FirebaseAuth.instance.currentUser != null;
  }

  // Request notification permission
  static Future<void> init() async {
    try {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: true,
        badge: true,
        carPlay: false,
        criticalAlert:
            false, // Changed to false as it requires special entitlement
        provisional: false,
        sound: true,
      );

      print('Notification permission granted: ${settings.authorizationStatus}');

      // Set iOS foreground notification presentation options
      await _firebaseMessaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      print('Error requesting notification permissions: $e');
    }
  }

  // Get the FCM device token
  static Future<String?> getDeviceToken({int maxRetries = 3}) async {
    try {
      String? token;
      if (kIsWeb) {
        // Get the device FCM token for web
        token = await _firebaseMessaging.getToken(vapidKey: "");
        print("Web device token: $token");
      } else {
        // Get the device FCM token for mobile
        token = await _firebaseMessaging.getToken();
        print("Mobile device token: $token");
      }

      if (token != null) {
        await saveTokenToFirestore(token: token);

        // Set up token refresh listener
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
          print("FCM token refreshed");
          saveTokenToFirestore(token: newToken);
        });
      }
      return token;
    } catch (e) {
      print("Failed to get device token: $e");
      if (maxRetries > 0) {
        print("Retrying after 10 seconds");
        await Future.delayed(const Duration(seconds: 10));
        return getDeviceToken(maxRetries: maxRetries - 1);
      }
      return null;
    }
  }

  static Future<void> saveTokenToFirestore({required String token}) async {
    if (!isUserLoggedIn()) {
      print("User not logged in, token not saved");
      return;
    }

    try {
      // Replace this with your actual token saving logic
      // For example, if you're using Firestore:
      // await FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).update({'fcmToken': token});
      print("Token saved to Firestore (implement your logic here)");
    } catch (e) {
      print("Error saving token: $e");
    }
  }

  static Future<void> localNotiInit() async {
    try {
      // Initialize platform-specific settings
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // Updated DarwinInitializationSettings without deprecated parameter
      const DarwinInitializationSettings initializationSettingsDarwin =
          DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
            defaultPresentAlert: true,
            defaultPresentBadge: true,
            defaultPresentSound: true,
          );

      const InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsDarwin,
          );

      // Request notification permissions for Android 13+
      final androidPlugin =
          _flutterLocalNotificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      if (androidPlugin != null) {
        await androidPlugin.requestNotificationsPermission();
      }

      // Initialize the plugin with notification tap handlers
      await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: onNotificationTap,
        onDidReceiveBackgroundNotificationResponse: onNotificationTap,
      );

      // Set up foreground handler
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print("Foreground message received: ${message.messageId}");
        _handleMessage(message);
      });

      // Setup background message handler
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print("Background message opened: ${message.messageId}");
        _handleMessage(message);
      });
    } catch (e) {
      print('Error initializing local notifications: $e');
    }
  }

  static void _handleMessage(RemoteMessage message) {
    if (message.notification != null) {
      showSimpleNotification(
        title: message.notification?.title ?? 'New Notification',
        body: message.notification?.body ?? '',
        payload: message.data.toString(),
      );
    }

    if (message.data.isNotEmpty) {
      final type = message.data['type'];
      final id = message.data['id'] ?? '';

      // Navigate based on notification type
      switch (type) {
        case 'message':
          navigatorKey.currentState?.pushNamed('/message', arguments: id);
          break;
        case 'event':
          navigatorKey.currentState?.pushNamed('/event', arguments: id);
          break;
        default:
          navigatorKey.currentState?.pushNamed('/notifications');
      }
    }
  }

  // Handle notification tap
  static void onNotificationTap(NotificationResponse notificationResponse) {
    print("Notification tapped: ${notificationResponse.payload}");
    navigatorKey.currentState?.pushNamed(
      "/message",
      arguments: notificationResponse,
    );
  }

  // Show a simple notification
  static Future<void> showSimpleNotification({
    required String? title,
    required String? body,
    required String payload,
  }) async {
    try {
      const AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
            'rit_club_channel',
            'RIT Club Notifications',
            channelDescription: 'Notifications for RIT Club app',
            importance: Importance.max,
            priority: Priority.high,
            ticker: 'ticker',
          );

      const DarwinNotificationDetails darwinNotificationDetails =
          DarwinNotificationDetails();

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails,
      );

      await _flutterLocalNotificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch, // More unique ID
        title ?? 'Notification',
        body ?? '',
        notificationDetails,
        payload: payload,
      );
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  // Setup everything in one call - ideal for splash screen
  static Future<void> setupNotifications() async {
    try {
      // Request permissions
      await init();

      // Initialize local notifications
      await localNotiInit();

      // Check for initial message (app opened from terminated state)
      final initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        // Delay to ensure app is initialized
        Future.delayed(const Duration(seconds: 1), () {
          _handleMessage(initialMessage);
        });
      }

      // Get token in background
      await getDeviceToken();
    } catch (e) {
      print('Error setting up notifications: $e');
    }
  }
}
