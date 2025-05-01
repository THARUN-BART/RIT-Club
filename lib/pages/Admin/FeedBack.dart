import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class feedback extends StatefulWidget {
  const feedback({super.key});

  @override
  State<feedback> createState() => _feedbackState();
}

class _feedbackState extends State<feedback> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "FeedBack",
          style: GoogleFonts.aclonica(fontSize: 25, color: Colors.white),
        ),
        centerTitle: true,
      ),
    );
  }
}
