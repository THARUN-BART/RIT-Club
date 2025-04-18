import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rit_club/pages/Admin/admin_home.dart';
import 'package:rit_club/pages/User/Home.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rit_club/pages/mainScreen.dart'; // For AdminMainScreen

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthState(); // Check Firebase Authentication state
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
    await Future.delayed(Duration(milliseconds: 1000)); // Splash delay

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
              MaterialPageRoute(
                builder: (context) => AdminHome(),
              ), // Replace with your admin screen
            );
          } else {
            // Navigate to regular Home page
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => HomePage()),
            );
          }
        } else {
          // If no role is found, redirect to login or handle accordingly
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
