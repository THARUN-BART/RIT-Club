import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StatusPage extends StatefulWidget {
  const StatusPage({super.key});

  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late TabController _tabController;
  List<String> _participatedEventIds = [];
  Stream<List<DocumentSnapshot>>? _activeEventsStream;
  Stream<List<DocumentSnapshot>>? _pastEventsStream;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchUserParticipatedEvents();
  }

  Future<void> _fetchUserParticipatedEvents() async {
    final userId = _auth.currentUser?.uid;
    if (userId != null) {
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          setState(() {
            _participatedEventIds = List<String>.from(
              userDoc.data()?['participatedEventIds'] ?? [],
            );
            _activeEventsStream = _getEventsByStatus('active');
            _pastEventsStream = _getEventsByStatus('past');
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint('Error fetching participated events: $e');
        setState(() {
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Stream<List<DocumentSnapshot>> _getEventsByStatus(String status) {
    if (_participatedEventIds.isEmpty) return Stream.value([]);
    return _firestore
        .collection('events')
        .where(FieldPath.documentId, whereIn: _participatedEventIds)
        .where('status', isEqualTo: status)
        .snapshots()
        .map((snapshot) => snapshot.docs);
  }

  Widget _buildEventCard(DocumentSnapshot event) {
    final data = event.data() as Map<String, dynamic>;
    final isActive = data['status']?.toString().toLowerCase() == 'active';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  data['title'] ?? 'No Title',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.green[50] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isActive ? 'ACTIVE' : 'PAST',
                    style: TextStyle(
                      color: isActive ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (data['description'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(data['description']!),
              ),
            if (data['eventDateTime'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      data['eventDateTime'] is Timestamp
                          ? _formatDate(
                            (data['eventDateTime'] as Timestamp).toDate(),
                          )
                          : data['eventDateTime'].toString(),
                    ),
                  ],
                ),
              ),
            if (data['location'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, size: 16),
                    const SizedBox(width: 8),
                    Text(data['location']!),
                  ],
                ),
              ),
            if (data['clubName'] != null)
              Row(
                children: [
                  const Icon(Icons.people, size: 16),
                  const SizedBox(width: 8),
                  Text('Organized by ${data['clubName']!}'),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "My Participated Events",
          style: GoogleFonts.aclonica(fontSize: 25, color: Colors.orangeAccent),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.orangeAccent,
          indicatorColor: Colors.orangeAccent,
          unselectedLabelColor: Colors.grey,
          tabs: const [Tab(text: 'Active Events'), Tab(text: 'Past Events')],
        ),
      ),
      body:
          _isLoading
              ? Container() // Empty container while loading
              : TabBarView(
                controller: _tabController,
                children: [
                  _buildEventList(_activeEventsStream ?? Stream.value([])),
                  _buildEventList(_pastEventsStream ?? Stream.value([])),
                ],
              ),
    );
  }

  Widget _buildEventList(Stream<List<DocumentSnapshot>> stream) {
    return StreamBuilder<List<DocumentSnapshot>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Container();

        final docs = snapshot.data ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No events found'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) => _buildEventCard(docs[index]),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
