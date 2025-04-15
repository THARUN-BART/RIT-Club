import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rit_club/Authentication/login.dart';
import 'package:rit_club/pages/Home.dart';
import 'package:google_fonts/google_fonts.dart';

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
        // Centers the entire content
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipOval(
              // Makes the image circular
              child: Image.asset(
                "assets/App_Ic/Club_Ic.jpg",
                height: 200,
                width: 200,
                fit: BoxFit.cover, // Ensures the image fills the circular frame
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
    await Future.delayed(
      Duration(milliseconds: 1000),
    ); // Simulates splash screen delay

    User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      // User is logged in; navigate to HomeScreen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => homePage()),
      );
    } else {
      // User is not logged in; navigate to Login screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => Login()),
      );
    }
  }
}
