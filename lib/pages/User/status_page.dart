import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class statusPage extends StatefulWidget {
  const statusPage({super.key});

  @override
  State<statusPage> createState() => _statusPageState();
}

class _statusPageState extends State<statusPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "My Status",
          style: GoogleFonts.aclonica(fontSize: 25, color: Colors.orangeAccent),
        ),
        centerTitle: true,
      ),
    );
  }
}
