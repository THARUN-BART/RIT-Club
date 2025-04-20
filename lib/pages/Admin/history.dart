import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class history extends StatefulWidget {
  const history({super.key});

  @override
  State<history> createState() => _historyState();
}

class _historyState extends State<history> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Event History", style: GoogleFonts.aclonica(fontSize: 25)),
      ),
    );
  }
}
