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
        centerTitle: true,
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text('Recent Events'),
            onTap: () {
              // Navigate to Recent Events
            },
          ),
          ListTile(
            title: Text('Event Highlights'),
            onTap: () {
              // Navigate to Event Highlights
            },
          ),
          ListTile(title: Text('FeedBack'), onTap: () {}),
        ],
      ),
    );
  }
}
