import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ClubAnnouncementPage extends StatefulWidget {
  final String clubId;
  final String clubName;

  const ClubAnnouncementPage({
    Key? key,
    required this.clubId,
    required this.clubName,
  }) : super(key: key);

  @override
  State<ClubAnnouncementPage> createState() => _ClubAnnouncementPageState();
}

class _ClubAnnouncementPageState extends State<ClubAnnouncementPage> {
  bool _isLoading = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _announcements = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchAnnouncements();
  }

  Future<void> _fetchAnnouncements() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final QuerySnapshot<Map<String, dynamic>> result =
          await FirebaseFirestore.instance
              .collection('clubs')
              .doc(widget.clubId)
              .collection('announcements')
              .get();

      final docs = result.docs;

      // Sort by timestamp (or similar fields) in descending order
      docs.sort((a, b) {
        final aTimestamp = _extractTimestamp(a.data());
        final bTimestamp = _extractTimestamp(b.data());
        return bTimestamp.compareTo(aTimestamp); // Descending
      });

      setState(() {
        _announcements = docs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  DateTime _extractTimestamp(Map<String, dynamic> data) {
    if (data.containsKey('timestamp') && data['timestamp'] is Timestamp) {
      return (data['timestamp'] as Timestamp).toDate();
    } else if (data.containsKey('createdAt') &&
        data['createdAt'] is Timestamp) {
      return (data['createdAt'] as Timestamp).toDate();
    } else if (data.containsKey('date') && data['date'] is Timestamp) {
      return (data['date'] as Timestamp).toDate();
    } else {
      return DateTime.fromMillisecondsSinceEpoch(0); // default old date
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "${widget.clubName} Announcements",
          style: GoogleFonts.roboto(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        foregroundColor: Colors.orangeAccent,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage.isNotEmpty
              ? _buildErrorView()
              : _buildAnnouncementsView(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Text(
              'Error loading announcements: $_errorMessage',
              style: GoogleFonts.roboto(fontSize: 16, color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Club ID: ${widget.clubId}',
            style: GoogleFonts.roboto(fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _fetchAnnouncements,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementsView() {
    if (_announcements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.announcement_outlined,
              size: 60,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 20),
            Text(
              'No announcements yet',
              style: GoogleFonts.roboto(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                'Check back later for updates from ${widget.clubName}',
                style: GoogleFonts.roboto(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _announcements.length,
      itemBuilder: (context, index) {
        final doc = _announcements[index];
        final data = doc.data();

        final title = data['title'] ?? data['subject'] ?? 'Announcement';
        final content =
            data['content'] ??
            data['message'] ??
            data['description'] ??
            'No details provided';
        final timestamp = _extractTimestamp(data);
        final dateStr = "${timestamp.day}/${timestamp.month}/${timestamp.year}";

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.roboto(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateStr,
                  style: GoogleFonts.roboto(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 12),
                Text(content, style: GoogleFonts.roboto(fontSize: 16)),
              ],
            ),
          ),
        );
      },
    );
  }
}
