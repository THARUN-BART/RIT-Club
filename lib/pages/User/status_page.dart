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
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<String> _participatedEventIds = [];
  Map<String, String> _eventOdStatus = {}; // Track OD status for each event

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchUserParticipatedEvents();
  }

  Future<void> _fetchUserParticipatedEvents() async {
    final userId = _auth.currentUser?.uid;
    if (userId != null) {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        setState(() {
          _participatedEventIds = List<String>.from(
            userDoc.data()?['participatedEventIds'] ?? [],
          );
        });
        // Fetch OD status for each event
        await _fetchOdStatusForEvents();
      }
    }
  }

  Future<void> _fetchOdStatusForEvents() async {
    Map<String, String> statusMap = {};
    for (String eventId in _participatedEventIds) {
      try {
        final eventDoc =
            await _firestore.collection('events').doc(eventId).get();
        if (eventDoc.exists) {
          // Check if OD letter is available (assuming there's a field 'odLetterUrl')
          final odLetterUrl = eventDoc.data()?['odLetterUrl'] as String?;
          statusMap[eventId] =
              odLetterUrl != null ? 'OD Available' : 'Waiting for OD';
        }
      } catch (e) {
        statusMap[eventId] = 'Error checking status';
      }
    }
    setState(() {
      _eventOdStatus = statusMap;
    });
  }

  Stream<List<DocumentSnapshot>> _getCurrentEvents() {
    if (_participatedEventIds.isEmpty) return Stream.value([]);

    // First get all events in batches of 10 (Firestore limitation for whereIn)
    return Stream.fromFuture(_fetchAllParticipatedEvents()).asyncMap((events) {
      // Then filter locally for current events
      final now = DateTime.now();
      return events.where((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) return false;

          final endDate = data['endDate']?.toDate();
          return endDate != null && endDate.isAfter(now);
        }).toList()
        ..sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          return (aData['endDate']?.toDate() ?? DateTime.now()).compareTo(
            bData['endDate']?.toDate() ?? DateTime.now(),
          );
        });
    });
  }

  Stream<List<DocumentSnapshot>> _getPastEvents() {
    if (_participatedEventIds.isEmpty) return Stream.value([]);

    // First get all events
    return Stream.fromFuture(_fetchAllParticipatedEvents()).asyncMap((events) {
      // Then filter locally for past events
      final now = DateTime.now();
      return events.where((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) return false;

          final endDate = data['endDate']?.toDate();
          return endDate != null && endDate.isBefore(now);
        }).toList()
        ..sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          return (bData['endDate']?.toDate() ?? DateTime.now()).compareTo(
            aData['endDate']?.toDate() ?? DateTime.now(),
          );
        });
    });
  }

  Future<List<DocumentSnapshot>> _fetchAllParticipatedEvents() async {
    if (_participatedEventIds.isEmpty) return [];

    List<DocumentSnapshot> allEvents = [];

    // Process IDs in batches of 10 (Firestore limitation for 'whereIn')
    for (int i = 0; i < _participatedEventIds.length; i += 10) {
      int end =
          (i + 10 < _participatedEventIds.length)
              ? i + 10
              : _participatedEventIds.length;

      List<String> batch = _participatedEventIds.sublist(i, end);

      final querySnapshot =
          await _firestore
              .collection('events')
              .where(FieldPath.documentId, whereIn: batch)
              .get();

      allEvents.addAll(querySnapshot.docs);
    }

    return allEvents;
  }

  Widget _buildEventList(Stream<List<DocumentSnapshot>> stream) {
    return StreamBuilder<List<DocumentSnapshot>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No events found'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var document = docs[index];
            Map<String, dynamic> data = document.data() as Map<String, dynamic>;
            final eventId = document.id;
            final odStatus = _eventOdStatus[eventId] ?? 'Status unknown';

            return Card(
              margin: const EdgeInsets.all(8),
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['title'] ?? 'No Title',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(data['description'] ?? 'No Description'),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Start: ${_formatDate(data['startDate']?.toDate())}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'End: ${_formatDate(data['endDate']?.toDate())}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    if (data['location'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, size: 16),
                            const SizedBox(width: 4),
                            Text(data['location']),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.description, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'OD Status: $odStatus',
                          style: TextStyle(
                            color:
                                odStatus == 'OD Available'
                                    ? Colors.green
                                    : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (data['odLetterUrl'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ElevatedButton(
                          onPressed: () {
                            // Implement PDF viewer/download functionality
                            _viewOdLetter(data['odLetterUrl']);
                          },
                          child: const Text('View OD Letter'),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _viewOdLetter(String url) {
    // Implement PDF viewing functionality
    // You might want to use a package like 'flutter_pdf_viewer' or 'advance_pdf_viewer'
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('OD Letter'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('OD letter is available for download.'),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    // Implement download functionality
                    Navigator.pop(context);
                  },
                  child: const Text('Download PDF'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "My Events",
          style: GoogleFonts.aclonica(fontSize: 25, color: Colors.orangeAccent),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.orangeAccent,
          indicatorColor: Colors.orangeAccent,
          unselectedLabelColor: Colors.grey,
          tabs: const [Tab(text: "Current Events"), Tab(text: "Past Events")],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEventList(_getCurrentEvents()),
          _buildEventList(_getPastEvents()),
        ],
      ),
    );
  }
}
