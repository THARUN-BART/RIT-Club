import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rit_club/firebase_options.dart';
import 'package:rit_club/pages/splash_screen.dart';
import 'package:rit_club/pages/User/EventPage.dart';
import 'package:rit_club/pages/User/Home.dart';
import 'package:rit_club/pages/Admin/admin_home.dart';
import 'package:rit_club/pages/mainScreen.dart';
import 'package:rit_club/utils/push_notifications.dart';

import 'notification_service.dart';

// Global navigator key for navigation from notifications
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  print("Handling background message: ${message.messageId}");

  if (message.notification != null) {
    // Save to local notifications if not web
    if (!kIsWeb) {
      await PushNotifications.showSimpleNotification(
        title: message.notification?.title ?? 'New Notification',
        body: message.notification?.body ?? '',
        payload: jsonEncode(message.data),
      );
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessage);

    // Set up foreground message handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("Foreground message received: ${message.messageId}");
      if (message.notification != null) {
        if (kIsWeb) {
          // Show dialog for web
          showDialog(
            context: navigatorKey.currentContext!,
            builder:
                (context) => AlertDialog(
                  title: Text(message.notification!.title ?? 'Notification'),
                  content: Text(message.notification!.body ?? ''),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('OK'),
                    ),
                  ],
                ),
          );
        } else {
          // Show local notification for mobile
          PushNotifications.showSimpleNotification(
            title: message.notification!.title ?? 'New Notification',
            body: message.notification!.body ?? '',
            payload: jsonEncode(message.data),
          );
        }
      }
    });

    // Handle when app is opened from terminated state
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationNavigation(initialMessage);
    }

    // Handle when app is opened from background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationNavigation);

    runApp(const RitClubApp());
  } catch (e) {
    print('Firebase initialization error: $e');
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Initialization failed. Please restart.')),
        ),
      ),
    );
  }
}

void _handleNotificationNavigation(RemoteMessage message) {
  if (message.data.containsKey('type')) {
    final type = message.data['type'];
    final id = message.data['id'] ?? '';

    switch (type) {
      case 'event':
        navigatorKey.currentState?.pushNamed('/event', arguments: id);
        break;
      // Add other notification types here
      default:
        navigatorKey.currentState?.pushNamed('/home');
    }
  }
}

class RitClubApp extends StatelessWidget {
  const RitClubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RIT Club',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      home: const SplashScreen(),
      routes: {
        '/home': (context) => const HomePage(),
        '/admin': (context) => const AdminHome(),
        '/event': (context) => const EventPage(),
        '/main': (context) => const ClubCircleButton(),
      },
    );
  }
}
