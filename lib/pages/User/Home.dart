import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rit_club/Authentication/login.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rit_club/pages/About.dart';
import 'package:rit_club/pages/User/ClubAnouncement.dart';
import 'package:rit_club/pages/User/EventPage.dart';
import 'package:rit_club/pages/User/status_page.dart';

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
  Map<String, List<Map<String, dynamic>>> _clubsByCategory = {};
  Map<String, List<Map<String, dynamic>>> _followedClubsByCategory = {};
  String? _userEmail;

  // Predefined categories
  final List<String> predefinedCategories = [
    'Social Service',
    'Language',
    'Multifaceted Activities',
    'Technical Enthusiasts',
    'Talent Showcase',
  ];

  // Pages for bottom navigation
  final List<Widget> _pages = [];

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const Login()),
      (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _userEmail = user?.email;
    _fetchUserData();
    _fetchClubs().then((_) {
      // Initialize pages after data is loaded
      setState(() {
        _pages.addAll([
          _buildHomeContent(),
          const EventPage(),
          const StatusPage(),
        ]);
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

  // Helper method to organize followed clubs by category
  void _organizeFollowedClubsByCategory() {
    Map<String, List<Map<String, dynamic>>> categorized = {};

    // Initialize all categories to ensure they appear even if empty
    for (var category in predefinedCategories) {
      categorized[category] = [];
    }

    // Sort followed clubs into categories
    for (var club in _followedClubs) {
      String category = club['category'] ?? '';
      if (predefinedCategories.contains(category)) {
        categorized[category]!.add(club);
      }
    }

    // Remove empty categories
    categorized.removeWhere((key, value) => value.isEmpty);

    setState(() {
      _followedClubsByCategory = categorized;
    });
  }

  Future<void> _fetchClubs() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

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

        // Initialize all predefined categories
        for (var category in predefinedCategories) {
          categorizedClubs[category] = [];
        }

        for (var doc in clubSnapshot.docs) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          String category = data['category'] ?? '';

          // Only include clubs with predefined categories
          if (predefinedCategories.contains(category)) {
            // Ensure followers is initialized
            List<String> followers = [];
            if (data.containsKey('followers')) {
              followers = List<String>.from(data['followers']);
            }

            // Make sure memberCount matches followers array length
            int memberCount = followers.length;

            Map<String, dynamic> clubData = {
              'id': doc.id,
              'name': data['name'] ?? 'Unknown Club',
              'description': data['description'] ?? 'No description available',
              'image': data['imageUrl'] ?? 'assets/default_club.png',
              'memberCount': memberCount,
              'category': category,
              'followers': followers, // Store followers array for easy checking
            };

            clubs.add(clubData);
            categorizedClubs[category]!.add(clubData);
          }
        }

        // Remove empty categories
        categorizedClubs.removeWhere((key, value) => value.isEmpty);

        setState(() {
          _allClubs = clubs;
          _clubsByCategory = categorizedClubs;
        });
      }

      // Now determine which clubs are followed
      List<Map<String, dynamic>> followed = [];

      if (user != null && _userEmail != null) {
        // For each club, check if user's email is in the followers array
        for (var club in _allClubs) {
          List<String> followers = [];
          if (club.containsKey('followers')) {
            followers = List<String>.from(club['followers']);
          }

          if (followers.contains(_userEmail)) {
            followed.add(Map<String, dynamic>.from(club));
          }
        }
      }

      setState(() {
        _followedClubs = followed;
        _isLoading = false;
      });

      // Organize followed clubs by category
      _organizeFollowedClubsByCategory();
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

  Future<void> _toggleFollowClub(
    String clubId,
    bool isCurrentlyFollowing,
  ) async {
    if (user == null || _userEmail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to follow clubs')),
      );
      return;
    }

    try {
      // Get current club data to check actual follow status
      final clubRef = FirebaseFirestore.instance
          .collection('clubs')
          .doc(clubId);
      DocumentSnapshot clubDoc = await clubRef.get();

      if (!clubDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Club not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Map<String, dynamic> clubData = clubDoc.data() as Map<String, dynamic>;
      String clubName = clubData['name'] ?? 'Unknown Club';
      List<String> clubFollowers = [];

      if (clubData.containsKey('followers')) {
        clubFollowers = List<String>.from(clubData['followers']);
      }

      // Check if user is actually following based on database
      bool isActuallyFollowing = clubFollowers.contains(_userEmail);

      // If UI state doesn't match database state, use database state
      if (isCurrentlyFollowing != isActuallyFollowing) {
        isCurrentlyFollowing = isActuallyFollowing;
      }

      // Show immediate feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 1),
          content: Text(
            isCurrentlyFollowing
                ? 'Unfollowing $clubName'
                : 'Following $clubName',
          ),
          backgroundColor: isCurrentlyFollowing ? Colors.red : Colors.green,
        ),
      );

      // Get current user data
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid);
      DocumentSnapshot userDoc = await userRef.get();
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      // Initialize or get followed clubs data
      List<String> followedClubIds = [];
      Map<String, String> followedClubNames = {};

      if (userData.containsKey('followedClubs')) {
        followedClubIds = List<String>.from(userData['followedClubs']);
      }
      if (userData.containsKey('followedClubNames')) {
        followedClubNames = Map<String, String>.from(
          userData['followedClubNames'],
        );
      }

      // Batch update to ensure atomic operation
      final batch = FirebaseFirestore.instance.batch();

      if (isCurrentlyFollowing) {
        // UNFOLLOW: Remove the club ID and name from user document
        followedClubIds.remove(clubId);
        followedClubNames.remove(clubId);

        // Remove user email from club's followers list
        clubFollowers.remove(_userEmail);
      } else {
        // FOLLOW: Add club ID and name to user document if not already present
        if (!followedClubIds.contains(clubId)) {
          followedClubIds.add(clubId);
          followedClubNames[clubId] = clubName;
        }

        // Add user email to club's followers list if not already present
        if (!clubFollowers.contains(_userEmail)) {
          clubFollowers.add(_userEmail!);
        }
      }

      // Update user document
      batch.update(userRef, {
        'followedClubs': followedClubIds,
        'followedClubNames': followedClubNames,
      });

      // Update club document with exact followers count
      batch.update(clubRef, {
        'memberCount': clubFollowers.length,
        'followers': clubFollowers,
      });

      await batch.commit();

      // Apply optimistic UI update
      setState(() {
        // Update all clubs list
        for (var club in _allClubs) {
          if (club['id'] == clubId) {
            List<String> followers = List<String>.from(club['followers'] ?? []);

            if (isCurrentlyFollowing) {
              followers.remove(_userEmail);
            } else if (!followers.contains(_userEmail)) {
              followers.add(_userEmail!);
            }

            club['followers'] = followers;
            club['memberCount'] = followers.length;
            break;
          }
        }

        // Update category lists
        for (var category in _clubsByCategory.keys) {
          for (var club in _clubsByCategory[category]!) {
            if (club['id'] == clubId) {
              List<String> followers = List<String>.from(
                club['followers'] ?? [],
              );

              if (isCurrentlyFollowing) {
                followers.remove(_userEmail);
              } else if (!followers.contains(_userEmail)) {
                followers.add(_userEmail!);
              }

              club['followers'] = followers;
              club['memberCount'] = followers.length;
              break;
            }
          }
        }

        // Update followed clubs list
        if (isCurrentlyFollowing) {
          _followedClubs.removeWhere((club) => club['id'] == clubId);
        } else {
          // Add to followed clubs if not already there
          if (!_followedClubs.any((club) => club['id'] == clubId)) {
            Map<String, dynamic>? clubToAdd = _allClubs.firstWhere(
              (club) => club['id'] == clubId,
              orElse: () => <String, dynamic>{},
            );

            if (clubToAdd.isNotEmpty) {
              _followedClubs.add(Map<String, dynamic>.from(clubToAdd));
            }
          }
        }

        // Re-organize followed clubs
        _organizeFollowedClubsByCategory();
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            isCurrentlyFollowing
                ? 'Successfully unfollowed $clubName'
                : 'Successfully followed $clubName',
          ),
          backgroundColor: isCurrentlyFollowing ? Colors.red : Colors.green,
        ),
      );

      // Refresh data to ensure consistency
      _fetchClubs();
    } catch (e) {
      print('Error toggling club follow: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('Failed to update: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
      // Refresh data to revert any incorrect UI updates
      _fetchClubs();
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

  bool _isClubFollowed(Map<String, dynamic> club) {
    if (_userEmail == null) return false;

    List<String> followers = [];
    if (club.containsKey('followers')) {
      followers = List<String>.from(club['followers']);
    }

    return followers.contains(_userEmail);
  }

  Widget _buildCategorizedClubsList(
    Map<String, List<Map<String, dynamic>>> categorizedClubs,
    bool isFollowedSection,
  ) {
    if (categorizedClubs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              isFollowedSection
                  ? "You're not following any clubs yet"
                  : "No clubs available",
              style: GoogleFonts.roboto(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: categorizedClubs.keys.length,
      itemBuilder: (context, index) {
        String category = categorizedClubs.keys.elementAt(index);
        List<Map<String, dynamic>> clubsInCategory =
            categorizedClubs[category]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                category,
                style: GoogleFonts.roboto(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.orangeAccent,
                ),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: clubsInCategory.length,
              itemBuilder: (context, clubIndex) {
                final club = clubsInCategory[clubIndex];
                final isFollowing = _isClubFollowed(club);

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: CircleAvatar(
                      backgroundImage: const AssetImage(
                        'assets/default_club.png',
                      ),
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
                            Icon(
                              Icons.people,
                              size: 16,
                              color: Colors.grey[600],
                            ),
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
                      onPressed:
                          () => _toggleFollowClub(club['id'], isFollowing),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isFollowing
                                ? Colors.grey[300]
                                : Colors.orangeAccent,
                        foregroundColor:
                            isFollowing ? Colors.black : Colors.white,
                      ),
                      child: Text(isFollowing ? 'Unfollow' : 'Follow'),
                    ),
                    onTap: () {
                      // If this is a followed club, navigate to the announcement page
                      if (isFollowedSection) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (context) => ClubAnnouncementPage(
                                  clubId: club['id'],
                                  clubName: club['name'],
                                ),
                          ),
                        );
                      } else {
                        // For clubs in the All Clubs tab, just show a snackbar for now
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('View details for ${club['name']}'),
                          ),
                        );
                      }
                    },
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildClubList(
    List<Map<String, dynamic>> clubs,
    bool isFollowedSection,
  ) {
    if (isFollowedSection && clubs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_add, size: 60, color: Colors.grey[400]),
            const SizedBox(height: 20),
            Text(
              "You're not following any clubs yet",
              style: GoogleFonts.roboto(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),
            Text(
              "Explore clubs and tap 'Follow' to add them here",
              style: GoogleFonts.roboto(fontSize: 14, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Switch to All Clubs tab
                _tabController.animateTo(0);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('Explore Clubs'),
            ),
          ],
        ),
      );
    }

    if (!isFollowedSection) {
      return _buildCategorizedClubsList(_clubsByCategory, false);
    } else {
      // Show followed clubs by category
      return _buildCategorizedClubsList(_followedClubsByCategory, true);
    }
  }

  Widget _buildHomeContent() {
    return Padding(
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
                    : Column(
                      children: [
                        TabBar(
                          controller: _tabController,
                          tabs: const [
                            Tab(text: 'All Clubs'),
                            Tab(text: 'Followed Clubs'),
                          ],
                          labelColor: Colors.orangeAccent,
                          unselectedLabelColor: Colors.grey,
                          indicatorColor: Colors.orangeAccent,
                        ),
                        Expanded(
                          child: TabBarView(
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          _selectedIndex == 0
              ? AppBar(
                title: Text(
                  "RIT CLUBS",
                  style: GoogleFonts.aclonica(
                    fontSize: 25,
                    color: Colors.orangeAccent,
                  ),
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
              )
              : null,
      body:
          _pages.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _pages[_selectedIndex],
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
