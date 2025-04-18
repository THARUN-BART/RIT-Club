import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rit_club/Authentication/login.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rit_club/pages/About.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late TabController _tabController;
  int _selectedIndex = 0;
  final User? user = FirebaseAuth.instance.currentUser;
  String _userName = 'User';
  List<Map<String, dynamic>> _allClubs = [];
  List<Map<String, dynamic>> _followedClubs = [];
  bool _isLoading = true;
  bool _hasError = false;
  // Map to store clubs grouped by category
  Map<String, List<Map<String, dynamic>>> _clubsByCategory = {};

  final List<Widget> pages = [ClubsPage(), MyEventsPage(), MyStatusPage()];
  void _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const Login()),
      (route) => false,
    );
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<void> _fetchUserData() async {
    if (user != null) {
      try {
        DocumentSnapshot userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user!.uid)
                .get();

        if (userDoc.exists && userDoc.data() != null) {
          setState(() {
            _userName = userDoc['name'] ?? 'User';
          });
        }
      } catch (e) {
        print('Error fetching user name: $e');
      }
    }
  }

  Future<void> _fetchClubs() async {
    try {
      bool clubsCollectionExists = await _checkCollectionExists('clubs');

      if (clubsCollectionExists) {
        QuerySnapshot clubSnapshot =
            await FirebaseFirestore.instance
                .collection('clubs')
                .orderBy('name')
                .get();

        List<Map<String, dynamic>> clubs = [];
        Map<String, List<Map<String, dynamic>>> categorizedClubs = {};

        for (var doc in clubSnapshot.docs) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          String category = data['category'] ?? 'Uncategorized';

          Map<String, dynamic> clubData = {
            'id': doc.id,
            'name': data['name'] ?? 'Unknown Club',
            'description': data['description'] ?? 'No description available',
            'image': data['imageUrl'] ?? 'assets/default_club.png',
            'memberCount': data['memberCount'] ?? 0,
            'category': category,
          };

          clubs.add(clubData);

          // Group by category
          if (!categorizedClubs.containsKey(category)) {
            categorizedClubs[category] = [];
          }
          categorizedClubs[category]!.add(clubData);
        }

        setState(() {
          _allClubs = clubs;
          _clubsByCategory = categorizedClubs;
        });
      }

      if (user != null) {
        try {
          DocumentSnapshot userDoc =
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user!.uid)
                  .get();

          List<String> followedClubIds = [];
          if (userDoc.exists &&
              userDoc.data() != null &&
              (userDoc.data() as Map<String, dynamic>).containsKey(
                'followedClubs',
              )) {
            followedClubIds = List<String>.from(userDoc['followedClubs']);
          }

          List<Map<String, dynamic>> followed = [];
          for (var club in _allClubs) {
            if (followedClubIds.contains(club['id'])) {
              followed.add(club);
            }
          }

          setState(() {
            _followedClubs = followed;
          });
        } catch (e) {
          print('Error fetching followed clubs: $e');
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching clubs: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<bool> _checkCollectionExists(String collectionName) async {
    try {
      QuerySnapshot snapshot =
          await FirebaseFirestore.instance
              .collection(collectionName)
              .limit(1)
              .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<void> _toggleFollowClub(String clubId, bool isFollowing) async {
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to follow clubs')),
      );
      return;
    }

    try {
      bool usersCollectionExists = await _checkCollectionExists('users');
      if (!usersCollectionExists) {
        await FirebaseFirestore.instance.collection('users').doc(user!.uid).set(
          {'followedClubs': [], 'name': user!.displayName ?? _userName},
          SetOptions(merge: true),
        );
      }

      DocumentReference userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid);

      DocumentReference clubRef = FirebaseFirestore.instance
          .collection('clubs')
          .doc(clubId);

      if (isFollowing) {
        // Unfollow: Remove club from user's followedClubs array and decrement memberCount
        await userRef.update({
          'followedClubs': FieldValue.arrayRemove([clubId]),
        });

        // Decrement the member count in the club document
        await clubRef.update({'memberCount': FieldValue.increment(-1)});

        setState(() {
          _followedClubs.removeWhere((club) => club['id'] == clubId);

          // Update member count in local lists
          for (var club in _allClubs) {
            if (club['id'] == clubId) {
              club['memberCount'] = (club['memberCount'] ?? 1) - 1;
              break;
            }
          }

          // Update in categorized list
          for (var category in _clubsByCategory.keys) {
            for (var club in _clubsByCategory[category]!) {
              if (club['id'] == clubId) {
                club['memberCount'] = (club['memberCount'] ?? 1) - 1;
                break;
              }
            }
          }
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Club unfollowed')));
      } else {
        // Follow: Add club to user's followedClubs array and increment memberCount
        await userRef.update({
          'followedClubs': FieldValue.arrayUnion([clubId]),
        });

        // Increment the member count in the club document
        await clubRef.update({'memberCount': FieldValue.increment(1)});

        Map<String, dynamic>? clubToFollow = _allClubs.firstWhere(
          (club) => club['id'] == clubId,
        );

        setState(() {
          // Increment the member count locally before adding to followed clubs
          clubToFollow['memberCount'] = (clubToFollow['memberCount'] ?? 0) + 1;
          _followedClubs.add(clubToFollow);

          // Update member count in all clubs list
          for (var club in _allClubs) {
            if (club['id'] == clubId) {
              club['memberCount'] = (club['memberCount'] ?? 0) + 1;
              break;
            }
          }

          // Update in categorized list
          for (var category in _clubsByCategory.keys) {
            for (var club in _clubsByCategory[category]!) {
              if (club['id'] == clubId) {
                club['memberCount'] = (club['memberCount'] ?? 0) + 1;
                break;
              }
            }
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Club followed successfully')),
        );
      }
    } catch (e) {
      print('Error toggling club follow: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update club subscription')),
      );
    }
  }

  String _getGreetingMessage() {
    int hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning, $_userName!';
    } else if (hour < 18) {
      return 'Good Afternoon, $_userName!';
    } else {
      return 'Good Evening, $_userName!';
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchUserData();
    _fetchClubs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildClubList(
    List<Map<String, dynamic>> clubs,
    bool isFollowedSection,
  ) {
    if (clubs.isEmpty) {
      return Center(
        child: Text(
          isFollowedSection
              ? "You're not following any clubs yet"
              : "No clubs available",
          style: GoogleFonts.roboto(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    if (!isFollowedSection) {
      // Group clubs by category for "All Clubs" tab
      return _buildCategorizedClubsList(_clubsByCategory);
    }

    // For "My Clubs" tab, show a regular list
    return ListView.builder(
      itemCount: clubs.length,
      itemBuilder: (context, index) {
        final club = clubs[index];
        final isFollowing = _followedClubs.any((c) => c['id'] == club['id']);

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: ListTile(
            contentPadding: const EdgeInsets.all(12),
            leading: CircleAvatar(
              backgroundImage: AssetImage('assets/default_club.png'),
              radius: 30,
            ),
            title: Text(
              club['name'],
              style: GoogleFonts.roboto(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  club['description'],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.roboto(fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.people, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${club['memberCount']} members',
                      style: GoogleFonts.roboto(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: ElevatedButton(
              onPressed: () => _toggleFollowClub(club['id'], isFollowing),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isFollowing ? Colors.grey[300] : Colors.orangeAccent,
                foregroundColor: isFollowing ? Colors.black : Colors.white,
              ),
              child: Text(isFollowing ? 'Unfollow' : 'Follow'),
            ),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('View details for ${club['name']}')),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCategorizedClubsList(
    Map<String, List<Map<String, dynamic>>> clubsByCategory,
  ) {
    List<String> categories = clubsByCategory.keys.toList();

    return ListView.builder(
      itemCount: categories.length,
      itemBuilder: (context, categoryIndex) {
        String category = categories[categoryIndex];
        List<Map<String, dynamic>> clubsInCategory = clubsByCategory[category]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category heading
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 16, bottom: 8),
              child: Text(
                category,
                style: GoogleFonts.roboto(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.orangeAccent,
                ),
              ),
            ),

            // Clubs in this category
            ...clubsInCategory.map((club) {
              final isFollowing = _followedClubs.any(
                (c) => c['id'] == club['id'],
              );

              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    backgroundImage: AssetImage('assets/default_club.png'),
                    radius: 30,
                  ),
                  title: Text(
                    club['name'],
                    style: GoogleFonts.roboto(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        club['description'],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.roboto(fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.people, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text(
                            '${club['memberCount']} members',
                            style: GoogleFonts.roboto(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: ElevatedButton(
                    onPressed: () => _toggleFollowClub(club['id'], isFollowing),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isFollowing ? Colors.grey[300] : Colors.orangeAccent,
                      foregroundColor:
                          isFollowing ? Colors.black : Colors.white,
                    ),
                    child: Text(isFollowing ? 'Unfollow' : 'Follow'),
                  ),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('View details for ${club['name']}'),
                      ),
                    );
                  },
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "RIT CLUBS",
          style: GoogleFonts.aclonica(fontSize: 25, color: Colors.orangeAccent),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => About()),
              );
            },
            icon: const Icon(Icons.account_circle),
            iconSize: 30,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'All Clubs'), Tab(text: 'Followed Clubs')],
          labelColor: Colors.orangeAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orangeAccent,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getGreetingMessage(),
              style: GoogleFonts.akronim(
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child:
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _hasError
                      ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Error loading clubs',
                              style: TextStyle(fontSize: 18, color: Colors.red),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _isLoading = true;
                                  _hasError = false;
                                });
                                _fetchClubs();
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                      : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildClubList(_allClubs, false),
                          _buildClubList(_followedClubs, true),
                        ],
                      ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Clubs'),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_note_outlined),
            label: 'My Events',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.access_time),
            label: 'My Status',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.orangeAccent,
        onTap: _onItemTapped,
      ),
    );
  }
}
