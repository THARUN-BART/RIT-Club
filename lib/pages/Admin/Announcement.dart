import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'admin_home.dart';

class AnnouncementPage extends StatefulWidget {
  const AnnouncementPage({Key? key}) : super(key: key);

  @override
  State<AnnouncementPage> createState() => _AnnouncementPageState();
}

class _AnnouncementPageState extends State<AnnouncementPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  bool _isUploading = false;
  List<DocumentSnapshot> _announcements = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadAnnouncements() async {
    if (AdminHome.currentClubId.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      QuerySnapshot querySnapshot =
          await FirebaseFirestore.instance
              .collection('clubs')
              .doc(AdminHome.currentClubId)
              .collection('announcements')
              .orderBy('createdAt', descending: true)
              .get();

      setState(() {
        _announcements = querySnapshot.docs;
        _isLoading = false;
      });
    } catch (e) {
      print("Error loading announcements: $e");
      setState(() {
        _isLoading = false;
      });
      _showSnackBar("Error loading announcements. Please try again.");
    }
  }

  void _showCreateAnnouncementDialog() {
    _titleController.clear();
    _contentController.clear();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text(
              "Create Announcement",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orangeAccent,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Title',
                      hintText: 'Enter announcement title',
                      labelStyle: TextStyle(color: Colors.orangeAccent),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.orangeAccent,
                          width: 2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      filled: true,
                      prefixIcon: Icon(Icons.title, color: Colors.orangeAccent),
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _contentController,
                    decoration: InputDecoration(
                      labelText: 'Content',
                      hintText: 'Enter Title of Announcement',
                      labelStyle: TextStyle(color: Colors.orangeAccent),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Colors.orangeAccent,
                          width: 2,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      filled: true,
                      prefixIcon: Icon(
                        Icons.description,
                        color: Colors.orangeAccent,
                      ),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 5,
                    textAlignVertical: TextAlignVertical.top,
                  ),
                ],
              ),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Cancel",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed:
                    _isUploading ? null : () => _createAnnouncement(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                child:
                    _isUploading
                        ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                        : const Text(
                          "Post",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
              ),
            ],
            actionsPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
    );
  }

  Future<void> _createAnnouncement(BuildContext dialogContext) async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      _showSnackBar("Please fill in all fields");
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || AdminHome.currentClubId.isEmpty) {
        throw Exception("User not logged in or club not selected");
      }

      await FirebaseFirestore.instance
          .collection('clubs')
          .doc(AdminHome.currentClubId)
          .collection('announcements')
          .add({
            'title': title,
            'content': content,
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': user.email,
            'clubId': AdminHome.currentClubId,
            'clubName': AdminHome.currentClubName,
          });

      Navigator.pop(dialogContext);
      _showSnackBar("Announcement posted successfully!");
      _loadAnnouncements();
    } catch (e) {
      print("Error creating announcement: $e");
      _showSnackBar("Error posting announcement: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _deleteAnnouncement(String announcementId) async {
    try {
      await FirebaseFirestore.instance
          .collection('clubs')
          .doc(AdminHome.currentClubId)
          .collection('announcements')
          .doc(announcementId)
          .delete();

      _showSnackBar("Announcement deleted successfully");
      _loadAnnouncements();
    } catch (e) {
      print("Error deleting announcement: $e");
      _showSnackBar("Error deleting announcement: ${e.toString()}");
    }
  }

  void _showDeleteConfirmation(String announcementId) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Delete Announcement"),
            content: const Text(
              "Are you sure you want to delete this announcement? This action cannot be undone.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteAnnouncement(announcementId);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("Delete"),
              ),
            ],
          ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "Announcements",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.orangeAccent,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child:
                _announcements.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.announcement,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "No announcements yet",
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _showCreateAnnouncementDialog,
                            icon: const Icon(Icons.add),
                            label: const Text("Create First Announcement"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      itemCount: _announcements.length,
                      padding: const EdgeInsets.all(8),
                      itemBuilder: (context, index) {
                        final announcement = _announcements[index];
                        final data =
                            announcement.data() as Map<String, dynamic>;

                        final title = data['title'] ?? 'No Title';
                        final content = data['content'] ?? 'No Content';
                        final createdBy = data['createdBy'] ?? 'Unknown';

                        Timestamp? timestamp = data['createdAt'];
                        String formattedDate = 'Date unknown';

                        if (timestamp != null) {
                          DateTime dateTime = timestamp.toDate();
                          formattedDate = DateFormat(
                            'MMM d, yyyy • h:mm a',
                          ).format(dateTime);
                        }

                        return Card(
                          elevation: 3,
                          margin: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      color: Colors.red,
                                      onPressed:
                                          () => _showDeleteConfirmation(
                                            announcement.id,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(content, style: TextStyle(fontSize: 16)),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'By: $createdBy',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                    Text(
                                      formattedDate,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
      floatingActionButton:
          _announcements.isNotEmpty
              ? FloatingActionButton(
                onPressed: _showCreateAnnouncementDialog,
                backgroundColor: Colors.orangeAccent,
                child: const Icon(Icons.add),
              )
              : null,
    );
  }
}
