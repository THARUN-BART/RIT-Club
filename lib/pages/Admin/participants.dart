import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class participants extends StatefulWidget {
  const participants({super.key});

  @override
  State<participants> createState() => _participantsState();
}

class _participantsState extends State<participants> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Participants", style: GoogleFonts.aclonica(fontSize: 25)),
      ),
    );
  }
}
