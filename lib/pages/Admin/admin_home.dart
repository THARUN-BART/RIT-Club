import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rit_club/pages/Admin/admin_events.dart';
import 'package:rit_club/pages/Admin/participants.dart';

import '../../Authentication/login.dart';
import '../About.dart';
import 'Announcement.dart';
import 'FeedBack.dart';
import 'gdrive.dart';

class ClubCreationPage extends StatefulWidget {
  const ClubCreationPage({super.key});

  @override
  State<ClubCreationPage> createState() => _ClubCreationPageState();
}

class _ClubCreationPageState extends State<ClubCreationPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _clubNameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String _selectedCategory = 'Social Service';
  final List<String> _categories = [
    'Social Service',
    'Language',
    'Multifaceted Activities',
    'Technical Enthusiasts',
    'Talent Showcase',
  ];

  String? _gdriveImageUrl;
  bool _isUploading = false;
  bool _isCheckingName = false;
  String _uploadStatus = '';

  @override
  void dispose() {
    _clubNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<bool> _checkClubNameExists(String clubName) async {
    setState(() {
      _isCheckingName = true;
    });

    try {
      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('clubs')
              .where('name', isEqualTo: clubName.trim())
              .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      print("Error checking club name: $e");
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingName = false;
        });
      }
    }
  }

  Future<void> _pickGDriveImage() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const GDriveImagePickerDialog(),
    );

    if (result != null) {
      setState(() {
        _gdriveImageUrl = result;
        _uploadStatus = 'Google Drive image selected successfully';
      });
    }
  }

  Future<void> _uploadClub() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar("Please complete all required fields");
      return;
    }

    final clubName = _clubNameController.text.trim();
    setState(() {
      _uploadStatus = 'Checking club name...';
    });

    final nameExists = await _checkClubNameExists(clubName);
    if (nameExists) {
      _showSnackBar(
        "Sorry, that club name has already been taken. Please choose another name.",
      );
      setState(() {
        _uploadStatus = '';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Uploading...';
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar("User not logged in");
        return;
      }

      await FirebaseFirestore.instance.collection('clubs').add({
        'name': clubName,
        'description': _descriptionController.text.trim(),
        'category': _selectedCategory,
        'imageUrl': _gdriveImageUrl ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.email,
        'adminIds': user.uid,
        'memberCount': 0,
        'followers': [],
      });

      _showSnackBar("Club created successfully!");

      _clubNameController.clear();
      _descriptionController.clear();
      setState(() {
        _gdriveImageUrl = null;
        _uploadStatus = '';
      });

      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AdminHome()),
        );
      }
    } catch (e) {
      print("Error uploading club: $e");
      _showSnackBar("Error: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Create New Club",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _clubNameController,
              decoration: InputDecoration(
                labelText: 'Club Name',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.group),
                suffixIcon:
                    _isCheckingName
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                        : null,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a club name';
                }
                if (value.length < 3) {
                  return 'Club name must be at least 3 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items:
                  _categories.map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedCategory = newValue;
                  });
                }
              },
              validator:
                  (value) => value == null ? 'Please select a category' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 3,
              validator:
                  (value) =>
                      value!.isEmpty ? 'Please enter a description' : null,
            ),
            const SizedBox(height: 16),
            _gdriveImageUrl != null
                ? Column(
                  children: [
                    Image.network(
                      _gdriveImageUrl!,
                      height: 200,
                      fit: BoxFit.cover,
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _gdriveImageUrl = null;
                        });
                      },
                      icon: const Icon(Icons.delete),
                      label: const Text("Remove Image"),
                    ),
                  ],
                )
                : TextButton.icon(
                  onPressed: _pickGDriveImage,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text("Upload Image from Google Drive"),
                ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _uploadClub,
              icon: const Icon(Icons.cloud_upload),
              label: const Text("Create Club"),
            ),
            if (_uploadStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Center(child: Text(_uploadStatus)),
              ),
          ],
        ),
      ),
    );
  }
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  static String currentClubId = '';
  static String currentClubName = '';

  static void resetClubInfo() {
    currentClubId = '';
    currentClubName = '';
  }

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _hasClubs = false;
  List<DocumentSnapshot> _userClubs = [];

  // Update the list to include a new AnnouncementPage
  final List<Widget> _pages = [
    const AdminDashboardPage(),
    const EventsPage(),
    Participants(clubName: AdminHome.currentClubName),
    const AnnouncementPage(), // New Announcement page
    FeedbackPage(
      clubId: AdminHome.currentClubId,
      clubName: AdminHome.currentClubName,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _checkIfAdminHasClubs();
  }

  Future<void> _checkIfAdminHasClubs() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('clubs')
              .where('adminIds', arrayContains: user.uid)
              .get();

      setState(() {
        _userClubs = querySnapshot.docs;
        _hasClubs = querySnapshot.docs.isNotEmpty;

        // Set the current club if we have one and it's not already set
        if (_hasClubs && AdminHome.currentClubId.isEmpty) {
          final firstClub = querySnapshot.docs.first;
          final data = firstClub.data();
          AdminHome.currentClubId = firstClub.id;
          AdminHome.currentClubName = data['name'] ?? 'Unknown Club';
        }

        _isLoading = false;
      });
    } catch (e) {
      print("Error checking admin status: $e");
      setState(() {
        _isLoading = false;
        _hasClubs = false;
      });
    }
  }

  void _switchClub(String clubId, String clubName) {
    setState(() {
      AdminHome.currentClubId = clubId;
      AdminHome.currentClubName = clubName;
    });
    // Refresh the current page to reflect the new club
    _pages[_selectedIndex] = _rebuildCurrentPage(_selectedIndex);
    setState(() {});
  }

  // Helper method to rebuild the current page - updated to include announcement page
  Widget _rebuildCurrentPage(int index) {
    switch (index) {
      case 0:
        return const AdminDashboardPage();
      case 1:
        return const EventsPage();
      case 2:
        return Participants(clubName: AdminHome.currentClubName);
      case 3:
        return const AnnouncementPage();
      case 4:
        return FeedbackPage(
          clubId: AdminHome.currentClubId,
          clubName: AdminHome.currentClubName,
        );
      default:
        return const AdminDashboardPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            "Club Admin Dashboard",
            style: TextStyle(fontSize: 20, color: Colors.orangeAccent),
          ),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasClubs) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Create Your First Club"),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const Login()),
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
        body: const ClubCreationPage(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Club Admin Dashboard",
              style: GoogleFonts.aclonica(
                fontSize: 18,
                color: Colors.orangeAccent,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (_userClubs.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(Icons.swap_horiz),
              tooltip: 'Switch Club',
              onSelected: (String clubId) {
                final club = _userClubs.firstWhere((c) => c.id == clubId);
                final data = club.data() as Map<String, dynamic>;
                _switchClub(clubId, data['name'] ?? 'Unknown Club');
              },
              itemBuilder: (BuildContext context) {
                return _userClubs.map((club) {
                  final data = club.data() as Map<String, dynamic>;
                  final name = data['name'] ?? 'Unknown Club';
                  return PopupMenuItem<String>(
                    value: club.id,
                    child: Text(name),
                  );
                }).toList();
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
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // First two items
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.dashboard,
                      color: _selectedIndex == 0 ? Colors.orangeAccent : null,
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedIndex = 0;
                        _pages[0] = _rebuildCurrentPage(0);
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.event,
                      color: _selectedIndex == 1 ? Colors.orangeAccent : null,
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedIndex = 1;
                        _pages[1] = _rebuildCurrentPage(1);
                      });
                    },
                  ),
                ],
              ),
            ),

            // Empty space for the FAB
            const SizedBox(width: 48),

            // Last two items
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.people,
                      color: _selectedIndex == 2 ? Colors.orangeAccent : null,
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedIndex = 2;
                        _pages[2] = _rebuildCurrentPage(2);
                      });
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.feedback,
                      color: _selectedIndex == 4 ? Colors.orangeAccent : null,
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedIndex = 4;
                        _pages[4] = _rebuildCurrentPage(4);
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor:
            _selectedIndex == 3 ? Colors.orangeAccent : Colors.blue,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () {
          setState(() {
            _selectedIndex = 3;
            _pages[3] = _rebuildCurrentPage(3);
          });
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  List<DocumentSnapshot> _clubs = [];
  bool _isLoading = true;
  final TextEditingController _editNameController = TextEditingController();
  final TextEditingController _editDescController = TextEditingController();
  final TextEditingController _editImageUrlController = TextEditingController();
  String _editCategory = 'Social Service';
  bool _isEditing = false;
  String? _editingClubId;
  List<String> _followers = [];
  bool _isLoadingFollowers = false;

  @override
  void initState() {
    super.initState();
    _loadAdminClubs();
  }

  Future<void> _loadAdminClubs() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (AdminHome.currentClubId.isNotEmpty) {
        final docSnapshot =
            await FirebaseFirestore.instance
                .collection('clubs')
                .doc(AdminHome.currentClubId)
                .get();

        if (docSnapshot.exists) {
          setState(() {
            _clubs = [docSnapshot];
            _isLoading = false;
          });
          _loadClubFollowers();
          return;
        }
      }

      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('clubs')
              .where('adminIds', arrayContains: user.uid)
              .get();

      setState(() {
        _clubs = querySnapshot.docs;
        _isLoading = false;

        if (_clubs.isNotEmpty && AdminHome.currentClubId.isEmpty) {
          AdminHome.currentClubId = _clubs[0].id;
          final data = _clubs[0].data() as Map<String, dynamic>;
          AdminHome.currentClubName = data['name'] ?? 'Unknown Club';
        }
      });

      _loadClubFollowers();
    } catch (e) {
      print("Error loading clubs: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadClubFollowers() async {
    if (AdminHome.currentClubId.isEmpty) return;

    setState(() {
      _isLoadingFollowers = true;
    });

    try {
      DocumentSnapshot clubDoc =
          await FirebaseFirestore.instance
              .collection('clubs')
              .doc(AdminHome.currentClubId)
              .get();

      if (clubDoc.exists && clubDoc.data() != null) {
        final data = clubDoc.data() as Map<String, dynamic>;
        List<dynamic>? followerEmails = data['followers'];

        setState(() {
          _followers = followerEmails?.cast<String>() ?? [];
          _isLoadingFollowers = false;
        });
      } else {
        setState(() {
          _followers = [];
          _isLoadingFollowers = false;
        });
      }
    } catch (e) {
      print("Error fetching followers: $e");
      setState(() {
        _isLoadingFollowers = false;
        _followers = [];
      });
    }
  }

  void _showUserDetailsDialog(DocumentSnapshot userDoc) {
    final userData = userDoc.data() as Map<String, dynamic>;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("User Details"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Name: ${userData['name'] ?? 'UserWithoutName'}"),
              Text("Email: ${userData['email'] ?? 'UserNotFound'}"),
              Text("Department: ${userData['department'] ?? 'dept'}"),
              Text("Register Number: ${userData['regNo'] ?? '123456789012'}"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchUserDetails(String email) async {
    try {
      QuerySnapshot querySnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: email)
              .get();

      if (querySnapshot.docs.isNotEmpty) {
        DocumentSnapshot userDoc = querySnapshot.docs.first;
        _showUserDetailsDialog(userDoc);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No user found with this email")),
        );
      }
    } catch (e) {
      print("Error fetching user details: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching user details: ${e.toString()}")),
      );
    }
  }

  Future<void> _startEditing(DocumentSnapshot club) async {
    final data = club.data() as Map<String, dynamic>;
    setState(() {
      _isEditing = true;
      _editingClubId = club.id;
      _editNameController.text = data['name'] ?? '';
      _editDescController.text = data['description'] ?? '';
      _editCategory = data['category'] ?? 'Social Service';
      _editImageUrlController.text =
          convertGoogleDriveLink(data['imageUrl']) ?? '';
    });
  }

  Future<void> _pickEditImage() async {
    final imageUrl = await showDialog<String>(
      context: context,
      builder: (context) => const GDriveImagePickerDialog(),
    );

    if (imageUrl != null) {
      setState(() {
        _editImageUrlController.text = imageUrl;
      });
    }
  }

  Future<void> _saveChanges() async {
    if (_editNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Club name cannot be empty")),
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _editingClubId == null) return;

      String? imageUrl =
          _editImageUrlController.text.trim().isNotEmpty
              ? _editImageUrlController.text.trim()
              : null;

      await FirebaseFirestore.instance
          .collection('clubs')
          .doc(_editingClubId)
          .update({
            'name': _editNameController.text.trim(),
            'description': _editDescController.text.trim(),
            'category': _editCategory,
            if (imageUrl != null) 'imageUrl': imageUrl,
          });

      if (_editingClubId == AdminHome.currentClubId) {
        AdminHome.currentClubName = _editNameController.text.trim();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Club updated successfully")),
      );

      await _loadAdminClubs();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error updating club: ${e.toString()}")),
      );
    } finally {
      setState(() {
        _isEditing = false;
        _editingClubId = null;
        _isLoading = false;
      });
    }
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editingClubId = null;
      _editImageUrlController.clear();
    });
  }

  Widget _buildEditForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextFormField(
            controller: _editNameController,
            decoration: const InputDecoration(
              labelText: 'Club Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _editCategory,
            items:
                [
                  'Social Service',
                  'Language',
                  'Multifaceted Activities',
                  'Technical Enthusiasts',
                  'Talent Showcase',
                ].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _editCategory = newValue;
                });
              }
            },
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _editDescController,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _editImageUrlController,
            decoration: InputDecoration(
              labelText: 'Google Drive Image URL',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.link),
                onPressed: _pickEditImage,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_editImageUrlController.text.isNotEmpty)
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    _editImageUrlController.text,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (context, error, stackTrace) => Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error,
                                color: Colors.red,
                                size: 50,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Invalid image URL',
                                style: TextStyle(color: Colors.red[700]),
                              ),
                            ],
                          ),
                        ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _editImageUrlController.clear();
                        });
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.image, size: 50, color: Colors.grey),
                    const SizedBox(height: 10),
                    const Text("No image selected"),
                    TextButton.icon(
                      onPressed: _pickEditImage,
                      icon: const Icon(Icons.add_photo_alternate),
                      label: const Text("Select from Google Drive"),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton.icon(
                onPressed: _cancelEditing,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.cancel),
                label: const Text("Cancel"),
              ),
              ElevatedButton.icon(
                onPressed: _saveChanges,
                icon: const Icon(Icons.save),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                label: const Text("Save Changes"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isEditing) {
      return _buildEditForm();
    }

    if (_clubs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "You haven't created any clubs yet",
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ClubCreationPage(),
                  ),
                ).then((value) {
                  if (value == true) {
                    _loadAdminClubs();
                  }
                });
              },
              icon: const Icon(Icons.add),
              label: const Text("Create New Club"),
            ),
          ],
        ),
      );
    }

    final currentClub = _clubs.firstWhere(
      (club) => club.id == AdminHome.currentClubId,
      orElse: () => _clubs[0],
    );

    final clubData = currentClub.data() as Map<String, dynamic>;
    final clubName = clubData['name'] ?? 'Unknown Club';
    final clubDescription = clubData['description'] ?? 'No description';
    final clubCategory = clubData['category'] ?? 'Uncategorized';
    final clubImageUrl = convertGoogleDriveLink(
      clubData['imageUrl'].toString(),
    );
    final memberCount = clubData['memberCount'] ?? 0;

    Future<bool> checkUserExists(String uid) async {
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return userDoc.exists;
    }

    Future<bool> checkUserRole(String uid) async {
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists && userDoc.get('role') == 'ADMIN') {
        return true; // User is already an admin
      }
      return false; // User is not an admin
    }

    Future<void> makeUserAdmin(String uid) async {
      DocumentReference userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid);

      QuerySnapshot clubsSnapshot =
          await FirebaseFirestore.instance
              .collection('clubs')
              .where('adminIds', isEqualTo: uid)
              .get();

      try {
        await userRef.update({'role': 'ADMIN'});
        print('User has been made an admin.');

        // Update each club where this user was admin
        for (var club in clubsSnapshot.docs) {
          await club.reference.update({
            'adminIds': uid,
            'previousAdminId': club.get(
              'adminIds',
            ), // Optional: Keep record of previous admin
          });

          // Optionally, update the previous admin's role back to 'USER'
          DocumentReference previousAdminRef = FirebaseFirestore.instance
              .collection('users')
              .doc(club.get('adminId'));

          await previousAdminRef.update({'role': 'USER'});
        }

        print('Updated clubs and previous admin role.');
      } catch (e) {
        print('Error updating user or clubs: $e');
      }
    }

    void showInputDialog(BuildContext context) {
      TextEditingController _controller = TextEditingController();

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Enter a UID of User'),
            content: TextField(
              controller: _controller,
              decoration: InputDecoration(hintText: 'Enter uid here...'),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  String uid = _controller.text.trim();

                  // Check if the user exists and their role
                  bool exists = await checkUserExists(uid);
                  bool isAdmin = await checkUserRole(uid);

                  if (!exists) {
                    // User does not exist, show error dialog
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text('Error'),
                          content: Text('User UID not found!'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: Text('OK'),
                            ),
                          ],
                        );
                      },
                    );
                  } else if (isAdmin) {
                    // User is already an admin, show failure dialog
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text('Operation Failed'),
                          content: Text('User is already an admin.'),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: Text('OK'),
                            ),
                          ],
                        );
                      },
                    );
                  } else {
                    // Show confirmation dialog before making user admin
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text('Confirm Action'),
                          content: Text(
                            'Are you sure you want to make this user an admin?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(
                                  context,
                                ).pop(); // Close confirmation dialog
                              },
                              child: Text('No'),
                            ),
                            TextButton(
                              onPressed: () async {
                                await makeUserAdmin(uid);
                                Navigator.of(
                                  context,
                                ).pop(); // Close confirmation dialog
                                Navigator.of(
                                  context,
                                ).pop(); // Close input dialog
                              },
                              child: Text('Yes'),
                            ),
                          ],
                        );
                      },
                    );
                  }
                },
                child: Text('OK'),
              ),
            ],
          );
        },
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                if (clubImageUrl != null && clubImageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: clubImageUrl,
                      height: 250,
                      width: double.infinity,
                      placeholder:
                          (context, url) => CircularProgressIndicator(),
                      errorWidget:
                          (context, url, error) =>
                              Icon(Icons.error, color: Colors.red, size: 50),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              clubName,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _startEditing(currentClub),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Chip(label: Text(clubCategory)),
                          const SizedBox(width: 8),
                          Chip(label: Text("Members: $memberCount")),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Description:",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(clubDescription),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () {
                              showInputDialog(context);
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.white,
                            ),
                            icon: Icon(
                              Icons.admin_panel_settings,
                            ), // Prefix icon
                            label: Text('Make As Admin'),
                          ),
                          // Additional widgets go here
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Club Followers",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoadingFollowers)
                    const Center(child: CircularProgressIndicator())
                  else if (_followers.isEmpty)
                    const Center(
                      child: Text(
                        "No followers yet",
                        style: TextStyle(fontSize: 16),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _followers.length,
                      itemBuilder: (context, index) {
                        final followerEmail = _followers[index];
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title: Text(followerEmail),
                          trailing: IconButton(
                            icon: const Icon(Icons.info_outline),
                            onPressed: () => _fetchUserDetails(followerEmail),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? convertGoogleDriveLink(String url) {
    final RegExp regex = RegExp(
      r'https:\/\/drive\.google\.com\/file\/d\/([a-zA-Z0-9_-]+)',
    );
    final match = regex.firstMatch(url);
    return match != null
        ? 'https://drive.google.com/uc?export=view&id=${match.group(1)}'
        : null;
  }

  @override
  void dispose() {
    _editNameController.dispose();
    _editDescController.dispose();
    _editImageUrlController.dispose();
    super.dispose();
  }
}
