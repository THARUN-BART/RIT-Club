import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rit_club/pages/Admin/admin_home.dart';
import 'package:rit_club/pages/User/Home.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rit_club/pages/mainScreen.dart';
import 'package:rit_club/utils/push_notifications.dart';

import '../notification_service.dart';

// Need to add the missing CRUDService to your project
class CRUDService {
  // Method to save user token to Firestore
  static Future<void> saveUserToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'fcmToken': token,
              'lastTokenUpdate': FieldValue.serverTimestamp(),
            });
      }
    } catch (e) {
      print('Error saving user token: $e');
    }
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  // Static method for saving user token - used by PushNotifications class
  static Future<void> saveUserToken(String token) async {
    await CRUDService.saveUserToken(token);
  }

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeAppAndCheckAuth();
  }

  Future<void> _initializeAppAndCheckAuth() async {
    try {
      // Initialize push notifications
      await PushNotifications.setupNotifications();

      // Standard splash screen delay
      await Future.delayed(Duration(milliseconds: 1000));

      // Check if user is already logged in
      _checkAuthState();
    } catch (e) {
      print('Error during app initialization: $e');
      // Fallback to basic auth check if notification setup fails
      _checkAuthState();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipOval(
              child: Image.asset(
                "assets/App_Ic/Club_Ic.jpg",
                height: 200,
                width: 200,
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(height: 30),
            Text(
              "RIT Club",
              style: GoogleFonts.play(fontSize: 40, color: Colors.black),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkAuthState() async {
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        // Get user data from Firestore
        DocumentSnapshot userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();

        if (userDoc.exists) {
          String role = userDoc['role'];

          if (role == 'ADMIN') {
            // Navigate to Admin page
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => AdminHome()),
            );
          } else {
            // Navigate to regular Home page
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => HomePage()),
            );
          }
        } else {
          // If no role is found, redirect to login
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => ClubCircleButton()),
          );
        }
      } catch (e) {
        print('Error fetching user role: $e');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ClubCircleButton()),
        );
      }
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => ClubCircleButton()),
      );
    }
  }
}
