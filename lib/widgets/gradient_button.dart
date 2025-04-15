import 'package:flutter/material.dart';

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final List<Color> gradientColors;
  final double borderRadius;

  const GradientButton({
    super.key,
    required this.text, // Button text
    required this.onPressed, // Callback when button is pressed
    this.gradientColors = const [
      Colors.blue,
      Colors.purple,
    ], // Default gradient
    this.borderRadius = 20.0, // Default rounded corners
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent, // Transparent for gradient
          shadowColor: Colors.transparent, // No shadow
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(color: Colors.white), // Customize text color
        ),
      ),
    );
  }
}
