import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rit_club/pages/About.dart';
import 'package:rit_club/pages/Admin/events.dart';
import 'package:rit_club/pages/Admin/history.dart';
import 'package:rit_club/pages/Admin/participants.dart';

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

  File? _imageFile;
  final picker = ImagePicker();
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

  Future<void> _pickImage() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        var status = await Permission.photos.request();
        if (status.isDenied || status.isPermanentlyDenied) {
          _showSnackBar(
            "Storage permission is required. Please enable it in settings.",
          );
          openAppSettings();
          return;
        }
      }

      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _uploadStatus = 'Image selected successfully';
        });
      }
    } catch (e) {
      _showSnackBar("Error picking image: ${e.toString()}");
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

      String? imageUrl;

      if (_imageFile != null) {
        setState(() {
          _uploadStatus = 'Uploading image...';
        });

        String fileName =
            '${DateTime.now().millisecondsSinceEpoch}_${user.uid}';
        Reference ref = FirebaseStorage.instance
            .ref()
            .child('club_images')
            .child(fileName);

        UploadTask uploadTask = ref.putFile(_imageFile!);

        uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
          double progress = snapshot.bytesTransferred / snapshot.totalBytes;
          setState(() {
            _uploadStatus =
                'Uploading: ${(progress * 100).toStringAsFixed(2)}%';
          });
        });

        TaskSnapshot snapshot = await uploadTask;
        imageUrl = await snapshot.ref.getDownloadURL();
      }

      setState(() {
        _uploadStatus = 'Saving club information...';
      });

      DocumentReference clubRef = await FirebaseFirestore.instance
          .collection('clubs')
          .add({
            'name': clubName,
            'description': _descriptionController.text.trim(),
            'category': _selectedCategory,
            'imageUrl': imageUrl ?? '',
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': user.email,
            'adminIds': [user.uid],
            'memberCount': 0,
          });

      await clubRef.collection('events').add({
        'name': 'Welcome to $clubName',
        'description':
            'This is your first club event. Edit or delete as needed.',
        'date': DateTime.now().add(const Duration(days: 7)),
        'createdAt': FieldValue.serverTimestamp(),
        'location': 'TBD',
        'participants': [],
      });

      _showSnackBar("Club created successfully!");

      _clubNameController.clear();
      _descriptionController.clear();
      setState(() {
        _imageFile = null;
        _uploadStatus = '';
      });

      if (context.mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const AdminHome()),
          );
        }
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
                      child: Text(
                        category[0].toUpperCase() + category.substring(1),
                      ),
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
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  _imageFile != null
                      ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(_imageFile!, fit: BoxFit.cover),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  _imageFile = null;
                                });
                              },
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      )
                      : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.image,
                              size: 50,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 10),
                            const Text("No image selected"),
                            TextButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.add_photo_alternate),
                              label: const Text("Select Image (Optional)"),
                            ),
                          ],
                        ),
                      ),
            ),
            if (_uploadStatus.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _uploadStatus,
                  style: const TextStyle(color: Colors.blue),
                ),
              ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: (_isUploading || _isCheckingName) ? null : _uploadClub,
              icon: const Icon(Icons.cloud_upload),
              label:
                  _isUploading
                      ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text("Creating Club..."),
                        ],
                      )
                      : const Text("Create Club"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _selectedIndex = 0;
  bool _isLoading = true;
  bool _hasClubs = false;

  final List<Widget> _pages = [
    const AdminDashboardPage(),
    const EventsPage(),
    const participants(),
    const history(),
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
              .limit(1)
              .get();

      setState(() {
        _hasClubs = querySnapshot.docs.isNotEmpty;
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Club Admin Dashboard")),
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
                  Navigator.of(context).pushReplacementNamed('/login');
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
        title: Text(
          "Club Admin Dashboard",
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
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.event), label: 'Events'),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Participants',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
        selectedItemColor: Colors.orangeAccent,
      ),
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
  String _editCategory = 'Social Service';
  File? _editImageFile;
  bool _isEditing = false;
  String? _editingClubId;
  String? _currentImageUrl;

  @override
  void initState() {
    super.initState();
    _loadAdminClubs();
  }

  Future<void> _loadAdminClubs() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('clubs')
              .where('adminIds', arrayContains: user.uid)
              .get();

      setState(() {
        _clubs = querySnapshot.docs;
        _isLoading = false;
      });
    } catch (e) {
      print("Error loading clubs: $e");
      setState(() {
        _isLoading = false;
      });
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
      _currentImageUrl = data['imageUrl'];
    });
  }

  Future<void> _pickEditImage() async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
      );
      if (pickedFile != null) {
        setState(() {
          _editImageFile = File(pickedFile.path);
          _currentImageUrl = null;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error picking image: ${e.toString()}")),
      );
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

      String? imageUrl = _currentImageUrl;

      // Handling image upload
      if (_editImageFile != null) {
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${user.uid}';
        final ref = FirebaseStorage.instance
            .ref()
            .child('club_images')
            .child(fileName);

        try {
          await ref.putFile(_editImageFile!);
          imageUrl = await ref.getDownloadURL();
        } catch (uploadError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error uploading image: ${uploadError.toString()}"),
            ),
          );
          setState(() {
            _isLoading = false;
          });
          return; // Stop further execution if upload fails
        }
      }

      // Updating the Firestore document
      await FirebaseFirestore.instance
          .collection('clubs')
          .doc(_editingClubId)
          .update({
            'name': _editNameController.text.trim(),
            'description': _editDescController.text.trim(),
            'category': _editCategory,
            if (imageUrl != null) 'imageUrl': imageUrl,
          });

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
        _editImageFile = null;
        _currentImageUrl = null;
        _isLoading = false;
      });
    }
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editingClubId = null;
      _editImageFile = null;
      _currentImageUrl = null;
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
          Container(
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                _editImageFile != null
                    ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(_editImageFile!, fit: BoxFit.cover),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () {
                              setState(() {
                                _editImageFile = null;
                              });
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    )
                    : _currentImageUrl != null
                    ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(_currentImageUrl!, fit: BoxFit.cover),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () {
                              setState(() {
                                _currentImageUrl = null;
                              });
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                            ),
                          ),
                        ),
                      ],
                    )
                    : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.image, size: 50, color: Colors.grey),
                          const SizedBox(height: 10),
                          const Text("No image selected"),
                          TextButton.icon(
                            onPressed: _pickEditImage,
                            icon: const Icon(Icons.add_photo_alternate),
                            label: const Text("Select Image (Optional)"),
                          ),
                        ],
                      ),
                    ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: _cancelEditing,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: _saveChanges,
                child: const Text("Save Changes"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClubList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Your Clubs",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (_clubs.isEmpty)
            const Center(child: Text("You don't have any clubs yet."))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _clubs.length,
              itemBuilder: (context, index) {
                final club = _clubs[index];
                final data = club.data() as Map<String, dynamic>;

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 3,
                  child: InkWell(
                    onTap: () {},
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (data['imageUrl'] != null &&
                            data['imageUrl'].isNotEmpty)
                          Container(
                            height: 150,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              image: DecorationImage(
                                image: NetworkImage(data['imageUrl']),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['name'] ?? 'Unnamed Club',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                data['description'] ?? 'No description',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              if (data['category'] != null)
                                Text(
                                  'Category: ${data['category'][0].toUpperCase() + data['category'].substring(1)}',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Members: ${data['memberCount'] ?? 0}',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () => _startEditing(club),
                                        tooltip: 'Edit Club',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
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

    return _buildClubList();
  }
}
