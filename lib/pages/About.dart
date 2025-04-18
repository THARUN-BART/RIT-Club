import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rit_club/Authentication/login.dart';

class About extends StatefulWidget {
  const About({super.key});

  @override
  State<About> createState() => _AboutState();
}

class _AboutState extends State<About> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<DocumentSnapshot> _getUserData() async {
    final user = _auth.currentUser;
    return await _firestore.collection('users').doc(user!.uid).get();
  }

  void _logout() async {
    await _auth.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const Login()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: Opacity(
            opacity: 0.9,
            child: Text(
              "ABOUT",
              style: GoogleFonts.aclonica(
                fontSize: 25,
                color: Colors.orangeAccent,
              ),
            ),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/background.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: FutureBuilder<DocumentSnapshot>(
            future: _getUserData(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(child: Text("User data not found"));
              }

              final data = snapshot.data!.data() as Map<String, dynamic>;

              return ListView(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  kToolbarHeight + 32,
                  16,
                  16,
                ),
                children: [
                  _buildTile("Name", data['name'] ?? "N/A"),
                  _buildTile("REGISTER NUMBER", data['regNo'] ?? "N/A"),
                  _buildTile("Email", data['email'] ?? "N/A"),
                  _buildTile("Role", data['role'] ?? "N/A"),
                  _buildTile("OD Count", data['odCount']?.toString() ?? "0"),
                  _buildTile(
                    "Blocked Until",
                    data['blockUntil'] != null
                        ? data['blockUntil'].toDate().toString()
                        : "Not Blocked",
                  ),
                  _buildTile(
                    "Followed Clubs",
                    data['followedClubs'] != null
                        ? (data['followedClubs'] as List<dynamic>).join(", ")
                        : "No clubs followed",
                  ),
                ],
              );
            },
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _logout,
          backgroundColor: Colors.red,
          child: const Icon(Icons.logout),
        ),
      ),
    );
  }

  Widget _buildTile(String title, String value) {
    return Opacity(
      opacity: 0.8,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: ListTile(
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.lightBlue,
            ),
          ),
          subtitle: Text(value, style: const TextStyle(color: Colors.white)),
          tileColor: Colors.black.withOpacity(0.3),
        ),
      ),
    );
  }
}
