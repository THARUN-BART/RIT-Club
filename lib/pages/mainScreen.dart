import 'package:flutter/material.dart';
import 'package:rit_club/Authentication/login.dart';

class ClubCircleButton extends StatelessWidget {
  const ClubCircleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: screenSize.width,
        height: screenSize.height,
        color: Colors.black, // Set your desired background color here
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Centered image without cropping or stretching
            Image.asset(
              'assets/ClubLogo/Background.jpg',
              fit: BoxFit.contain, // Keeps full image visible
            ),

            // Tappable center circle
            GestureDetector(
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const Login()),
                );
              },
              child: Container(
                width: screenSize.width * 0.4,
                height: screenSize.width * 0.4,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
