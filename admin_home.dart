import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rit_club/pages/About.dart';

class adminHome extends StatefulWidget {
  const adminHome({super.key});

  @override
  State<adminHome> createState() => _adminHomeState();
}

class _adminHomeState extends State<adminHome> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text("Hell mister Admin")));
  }
}
