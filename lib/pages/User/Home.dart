import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rit_club/Authentication/login.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rit_club/pages/About.dart';
import 'package:rit_club/pages/User/ClubAnouncement.dart';
import 'package:rit_club/pages/User/EventPage.dart';
import 'package:rit_club/pages/User/status_page.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'notification.dart';
import 'notification_batch.dart';

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

  // Map to track follow/unfollow operations in progress
  final Map<String, bool> _processingClubs = {};

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _userEmail = user?.email;
    _fetchUserData();
    _fetchClubs().then((_) {
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
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
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

        if (predefinedCategories.contains(category)) {
          List<String> followers = [];
          if (data.containsKey('followers')) {
            followers = List<String>.from(data['followers']);
          }

          Map<String, dynamic> clubData = {
            'id': doc.id,
            'name': data['name'] ?? 'Unknown Club',
            'description': data['description'] ?? 'No description available',
            'imageUrl': data['imageUrl'] ?? '', // Use imageUrl from database
            'memberCount': followers.length,
            'category': category,
            'followers': followers,
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

      // Determine which clubs are followed
      List<Map<String, dynamic>> followed = [];
      if (user != null && _userEmail != null) {
        for (var club in _allClubs) {
          List<String> followers = List<String>.from(club['followers'] ?? []);
          if (followers.contains(_userEmail)) {
            followed.add(Map<String, dynamic>.from(club));
          }
        }
      }

      setState(() {
        _followedClubs = followed;
        _isLoading = false;
      });

      _organizeFollowedClubsByCategory();
    } catch (e) {
      print('Error fetching clubs: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  void _organizeFollowedClubsByCategory() {
    Map<String, List<Map<String, dynamic>>> categorized = {};
    for (var category in predefinedCategories) {
      categorized[category] = [];
    }

    for (var club in _followedClubs) {
      String category = club['category'] ?? '';
      if (predefinedCategories.contains(category)) {
        categorized[category]!.add(club);
      }
    }

    categorized.removeWhere((key, value) => value.isEmpty);

    setState(() {
      _followedClubsByCategory = categorized;
    });
  }

  Future<void> _toggleFollowClub(
    String clubId,
    bool isCurrentlyFollowing,
  ) async {
    if (user == null || _userEmail == null) return;

    // Prevent multiple clicks while processing
    if (_processingClubs[clubId] == true) return;

    _processingClubs[clubId] = true;

    // Get club data from local state
    Map<String, dynamic>? clubData;
    for (var club in _allClubs) {
      if (club['id'] == clubId) {
        clubData = Map<String, dynamic>.from(club);
        break;
      }
    }

    if (clubData == null) {
      _processingClubs[clubId] = false;
      return;
    }

    String clubName = clubData['name'];
    List<String> clubFollowers = List<String>.from(clubData['followers'] ?? []);

    // Update UI immediately (optimistic update)
    setState(() {
      // Update the club in _allClubs
      for (var i = 0; i < _allClubs.length; i++) {
        if (_allClubs[i]['id'] == clubId) {
          if (isCurrentlyFollowing) {
            // Remove user from followers
            clubFollowers.remove(_userEmail);
            _allClubs[i]['followers'] = clubFollowers;
            _allClubs[i]['memberCount'] = clubFollowers.length;
          } else {
            // Add user to followers
            if (!clubFollowers.contains(_userEmail)) {
              clubFollowers.add(_userEmail!);
              _allClubs[i]['followers'] = clubFollowers;
              _allClubs[i]['memberCount'] = clubFollowers.length;
            }
          }
          break;
        }
      }

      // Update _followedClubs list
      if (isCurrentlyFollowing) {
        _followedClubs.removeWhere((club) => club['id'] == clubId);
      } else {
        final clubToAdd = _allClubs.firstWhere((club) => club['id'] == clubId);
        if (!_followedClubs.any((club) => club['id'] == clubId)) {
          _followedClubs.add(Map<String, dynamic>.from(clubToAdd));
        }
      }

      // Reorganize followed clubs by category
      _organizeFollowedClubsByCategory();
    });

    // Show immediate feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isCurrentlyFollowing ? 'Unfollowed $clubName' : 'Followed $clubName',
        ),
        backgroundColor: isCurrentlyFollowing ? Colors.red : Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      // Update database in background
      final clubRef = FirebaseFirestore.instance
          .collection('clubs')
          .doc(clubId);

      await clubRef.update({
        'memberCount': clubFollowers.length,
        'followers': clubFollowers,
      });

      // Update user's followed clubs
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid);

      if (isCurrentlyFollowing) {
        await userRef.update({
          'followedClubs': FieldValue.arrayRemove([clubId]),
        });
      } else {
        await userRef.update({
          'followedClubs': FieldValue.arrayUnion([clubId]),
          'followedClubNames.$clubId': clubName,
        });
      }
    } catch (e) {
      print('Error toggling club follow: $e');

      // Revert optimistic update on error
      _fetchClubs(); // Refresh data from server

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      _processingClubs[clubId] = false;
    }
  }

  String _getGreetingMessage() {
    int hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning, $_userName!';
    if (hour < 18) return 'Good Afternoon, $_userName!';
    return 'Good Evening, $_userName!';
  }

  bool _isClubFollowed(Map<String, dynamic> club) {
    if (_userEmail == null) return false;
    return List<String>.from(club['followers'] ?? []).contains(_userEmail);
  }

  Widget _buildClubCard(Map<String, dynamic> club, bool isFollowedSection) {
    final isFollowing = _isClubFollowed(club);
    final imageUrl = convertGoogleDriveLink(club['imageUrl'] ?? '') ?? '';
    final bool isProcessing = _processingClubs[club['id']] == true;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 30,
          backgroundColor: Colors.grey[200],
          backgroundImage:
              imageUrl.isNotEmpty
                  ? CachedNetworkImageProvider(imageUrl)
                  : const AssetImage('assets/default_club.png')
                      as ImageProvider,
          child:
              imageUrl.isEmpty
                  ? const Icon(Icons.group, size: 30, color: Colors.grey)
                  : null,
        ),
        title: Text(
          club['name'],
          style: GoogleFonts.roboto(fontSize: 18, fontWeight: FontWeight.bold),
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
          onPressed:
              isProcessing
                  ? null // Disable button while processing
                  : () => _toggleFollowClub(club['id'], isFollowing),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isFollowing ? Colors.grey[300] : Colors.orangeAccent,
            foregroundColor: isFollowing ? Colors.black : Colors.white,
          ),
          child:
              isProcessing
                  ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isFollowing ? Colors.black : Colors.white,
                      ),
                    ),
                  )
                  : Text(isFollowing ? 'Unfollow' : 'Follow'),
        ),
        onTap: () {
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
          }
        },
      ),
    );
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
            Icon(
              isFollowedSection ? Icons.group_add : Icons.error_outline,
              size: 60,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 20),
            Text(
              isFollowedSection
                  ? "You're not following any clubs yet"
                  : "No clubs available",
              style: GoogleFonts.roboto(fontSize: 18, color: Colors.grey[600]),
            ),
            if (isFollowedSection) ...[
              const SizedBox(height: 10),
              Text(
                "Explore clubs and tap 'Follow' to add them here",
                style: GoogleFonts.roboto(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _tabController.animateTo(0),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Explore Clubs'),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: categorizedClubs.keys.length,
      itemBuilder: (context, index) {
        String category = categorizedClubs.keys.elementAt(index);
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
            ...categorizedClubs[category]!.map(
              (club) => _buildClubCard(club, isFollowedSection),
            ),
          ],
        );
      },
    );
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
                            onPressed: _fetchClubs,
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
                              _buildCategorizedClubsList(
                                _clubsByCategory,
                                false,
                              ),
                              _buildCategorizedClubsList(
                                _followedClubsByCategory,
                                true,
                              ),
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
                  NotificationBadge(
                    child: const Icon(Icons.notifications),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const EventNotification(),
                        ),
                      );
                    },
                  ),
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

String? convertGoogleDriveLink(String url) {
  if (url.isEmpty) return null;
  final RegExp regex = RegExp(
    r'https:\/\/drive\.google\.com\/file\/d\/([a-zA-Z0-9_-]+)',
  );
  final match = regex.firstMatch(url);
  return match != null
      ? 'https://drive.google.com/uc?export=view&id=${match.group(1)}'
      : null;
}
