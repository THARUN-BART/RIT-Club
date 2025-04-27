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

  Future<Map<String, dynamic>> _getUserDataWithClubDetails() async {
    final user = _auth.currentUser;

    // Get the user document
    final userDoc = await _firestore.collection('users').doc(user!.uid).get();
    final userData = userDoc.data() as Map<String, dynamic>;

    // Create a result map
    final result = {'userData': userData};

    // If user has followedClubs, fetch club details
    if (userData['followedClubs'] != null &&
        userData['followedClubs'] is List) {
      final clubDetails = <String, Map<String, dynamic>>{};

      for (final clubId in userData['followedClubs']) {
        try {
          final clubDoc =
              await _firestore.collection('clubs').doc(clubId).get();
          if (clubDoc.exists) {
            clubDetails[clubId] = clubDoc.data() as Map<String, dynamic>;
          }
        } catch (e) {
          print('Error fetching club $clubId: $e');
        }
      }

      result['clubDetails'] = clubDetails;
    }

    return result;
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
          child: FutureBuilder<Map<String, dynamic>>(
            future: _getUserDataWithClubDetails(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData) {
                return const Center(child: Text("User data not found"));
              }

              final data = snapshot.data!['userData'] as Map<String, dynamic>;
              final clubsData =
                  snapshot.data!['clubDetails'] as Map<String, dynamic>?;
              final isAdmin = (data['role'] ?? "").toLowerCase() == "admin";

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
                  _buildTile("Department", data['department'] ?? "N/A"),
                  if (!isAdmin) ...[
                    _buildTile("OD Count", data['odCount']?.toString() ?? "0"),
                    _buildTile(
                      "Blocked Until",
                      data['blockUntil'] != null
                          ? data['blockUntil'].toDate().toString()
                          : "Not Blocked",
                    ),

                    // Section title for clubs
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                      child: Text(
                        "FOLLOWED CLUBS",
                        style: GoogleFonts.aclonica(
                          fontSize: 20,
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ),

                    // Display club details with expanded information
                    if (clubsData != null && clubsData.isNotEmpty)
                      ...clubsData.entries.map(
                        (entry) => _buildClubDetailCard(entry.value),
                      ),

                    // Fallback if club details couldn't be fetched but names are available
                    if (clubsData == null && data['followedClubNames'] != null)
                      _buildClubsList(
                        "Followed Clubs",
                        data['followedClubNames'],
                      ),

                    // Last fallback - just show IDs if nothing else is available
                    if (clubsData == null &&
                        data['followedClubNames'] == null &&
                        data['followedClubs'] != null)
                      _buildTile(
                        "Followed Clubs",
                        (data['followedClubs'] as List<dynamic>).join(", "),
                      ),
                  ],
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

  Widget _buildClubDetailCard(Map<String, dynamic> clubData) {
    return Opacity(
      opacity: 0.8,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        color: Colors.black.withOpacity(0.3),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      clubData['name'] ?? "Club Name",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.lightBlue,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  if (clubData['status'] != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            clubData['status'] == 'active'
                                ? Colors.green
                                : Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        clubData['status'],
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (clubData['description'] != null)
                Text(
                  clubData['description'],
                  style: const TextStyle(color: Colors.white70),
                ),
              const SizedBox(height: 8),
              if (clubData['department'] != null)
                Text(
                  "Department: ${clubData['department']}",
                  style: const TextStyle(color: Colors.white),
                ),
              if (clubData['head'] != null)
                Text(
                  "Head: ${clubData['head']}",
                  style: const TextStyle(color: Colors.white),
                ),
              if (clubData['createdAt'] != null)
                Text(
                  "Founded: ${(clubData['createdAt'] as Timestamp).toDate().toString().split(' ')[0]}",
                  style: const TextStyle(color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClubsList(String title, Map<String, dynamic> clubsMap) {
    // Extract club names from the map
    List<String> clubNames = [];
    clubsMap.forEach((key, value) {
      if (value is String) {
        clubNames.add(value);
      }
    });

    return Opacity(
      opacity: 0.8,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        color: Colors.black.withOpacity(0.3),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.lightBlue,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              ...clubNames
                  .map(
                    (club) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Text(
                        "• $club",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                  ,
            ],
          ),
        ),
      ),
    );
  }
}
