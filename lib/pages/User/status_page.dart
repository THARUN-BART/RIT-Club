import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:intl/intl.dart';

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
  Stream<List<DocumentSnapshot>>? _cancelledEventsStream;
  bool _isLoading = true;
  String? _currentUserName;
  Map<String, bool> _letterGenerationStatus = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this); // Updated to 3 tabs
    _fetchUserData();
    _checkRegistrationEndDates();
    _ensureODCountField(); // Ensure OD count field exists
  }

  // Make sure the odCount field exists in the user document
  Future<void> _ensureODCountField() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      final userRef = _firestore.collection('users').doc(userId);
      final userDoc = await userRef.get();

      if (userDoc.exists) {
        final userData = userDoc.data();
        // If odCount doesn't exist, initialize it
        if (!userData!.containsKey('odCount')) {
          await userRef.update({'odCount': 0});
        }
        // If processedCancelledEvents doesn't exist, initialize it
        if (!userData.containsKey('processedCancelledEvents')) {
          await userRef.update({'processedCancelledEvents': []});
        }
      }
    } catch (e) {
      debugPrint('Error ensuring OD count field: $e');
    }
  }

  Future<void> _fetchUserData() async {
    final userId = _auth.currentUser?.uid;
    if (userId != null) {
      try {
        final userDoc = await _firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          setState(() {
            _participatedEventIds = List<String>.from(
              userDoc.data()?['participatedEventIds'] ?? [],
            );
            _currentUserName = userDoc.data()?['name'] ?? 'User';
            _activeEventsStream = _getEventsByStatus('active');
            _pastEventsStream = _getEventsByStatus('past');
            _cancelledEventsStream = _getEventsByStatus('cancelled');
            _checkExistingLetters();
            _isLoading = false;
          });
        }
      } catch (e) {
        debugPrint('Error fetching user data: $e');
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

  Future<void> _checkExistingLetters() async {
    if (_participatedEventIds.isEmpty) return;

    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    try {
      // Get all event letters for this user
      final lettersSnapshot =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('eventLetters')
              .get();

      setState(() {
        for (var letterDoc in lettersSnapshot.docs) {
          _letterGenerationStatus[letterDoc.id] = true;
        }
      });
    } catch (e) {
      debugPrint('Error checking existing letters: $e');
    }
  }

  // Check for events where registration has ended and generate letters
  Future<void> _checkRegistrationEndDates() async {
    if (_participatedEventIds.isEmpty) return;

    final now = DateTime.now();
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    // Get all active events where user is participating
    final eventsSnapshot =
        await _firestore
            .collection('events')
            .where(FieldPath.documentId, whereIn: _participatedEventIds)
            .where('status', isEqualTo: 'active')
            .get();

    for (var eventDoc in eventsSnapshot.docs) {
      final data = eventDoc.data();

      // Check if registration end date exists and has passed
      if (data['registrationEndDate'] != null) {
        final registrationEndDate =
            (data['registrationEndDate'] as Timestamp).toDate();

        if (now.isAfter(registrationEndDate)) {
          // Check if letter already exists
          final letterDoc =
              await _firestore
                  .collection('users')
                  .doc(userId)
                  .collection('eventLetters')
                  .doc(eventDoc.id)
                  .get();

          if (!letterDoc.exists) {
            // Generate letter for events where registration ended
            await _generateEventLetter(
              eventDoc.id,
              data['title'] ?? 'Event',
              (data['eventDateTime'] as Timestamp).toDate(),
            );
          }

          setState(() {
            _letterGenerationStatus[eventDoc.id] = true;
          });
        }
      }
    }
  }

  Future<void> _generateEventLetter(
    String eventId,
    String eventName,
    DateTime eventDate,
  ) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null || _currentUserName == null) return;

      // Create a PDF document
      final pdf = pw.Document();

      // Add content to the PDF
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Text(
                    'Event Participation Letter',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Date: ${DateFormat('dd MMMM yyyy').format(DateTime.now())}',
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 30),
                pw.Text(
                  'Dear $_currentUserName,',
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'This letter confirms your registration for the following event:',
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 20),
                pw.Container(
                  padding: pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(),
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Event Name: $eventName',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Event Date: ${DateFormat('dd MMMM yyyy').format(eventDate)}',
                        style: pw.TextStyle(fontSize: 12),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Participant: $_currentUserName',
                        style: pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 30),
                pw.Text(
                  'Please keep this letter as confirmation of your registration. We look forward to your participation.',
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 20),
                pw.Text('Sincerely,', style: pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 10),
                pw.Text('Event Organizers', style: pw.TextStyle(fontSize: 12)),
              ],
            );
          },
        ),
      );

      // Save the PDF to a file
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$eventName-registration-letter.pdf');
      await file.writeAsBytes(await pdf.save());

      // Save the letter reference to Firestore
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('eventLetters')
          .doc(eventId)
          .set({
            'eventId': eventId,
            'eventName': eventName,
            'eventDate': Timestamp.fromDate(eventDate),
            'generatedDate': Timestamp.fromDate(DateTime.now()),
            'letterPath': file.path,
          });

      setState(() {
        _letterGenerationStatus[eventId] = true;
      });

      // Show notification to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration letter generated for $eventName'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => OpenFile.open(file.path),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error generating event letter: $e');
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

  // New method to handle OD count reduction for cancelled events
  Future<void> _decrementODCount(String eventId) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      // Get current OD count
      final DocumentReference userRef = _firestore
          .collection('users')
          .doc(userId);

      // Use a transaction to ensure data consistency
      await _firestore
          .runTransaction((transaction) async {
            DocumentSnapshot userDoc = await transaction.get(userRef);

            if (!userDoc.exists) return null;

            // Get current OD count and processed events
            final Map<String, dynamic> userData =
                userDoc.data() as Map<String, dynamic>;
            final int currentODCount = userData['odCount'] ?? 0;
            final List<String> processedCancelledEvents = List<String>.from(
              userData['processedCancelledEvents'] ?? [],
            );

            // If we've already processed this cancelled event, don't do anything
            if (processedCancelledEvents.contains(eventId)) {
              return null;
            }

            // Calculate new OD count (ensure it doesn't go below 0)
            final int newODCount = currentODCount > 0 ? currentODCount - 1 : 0;

            // Add this event to the processed list
            processedCancelledEvents.add(eventId);

            // Update user document with new OD count and processed events list
            transaction.update(userRef, {
              'odCount': newODCount,
              'processedCancelledEvents': processedCancelledEvents,
            });

            return newODCount;
          })
          .then((newCount) {
            // Show notification to user about OD reduction if count was updated
            if (newCount != null && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'OD count reduced by 1 due to cancelled event (now: $newCount)',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
            }
          });
    } catch (e) {
      debugPrint('Error decrementing OD count: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update OD count: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildEventCard(DocumentSnapshot event) {
    final data = event.data() as Map<String, dynamic>;
    final status = data['status']?.toString().toLowerCase() ?? '';
    final isActive = status == 'active';
    final isCancelled = status == 'cancelled';
    final hasRegistrationEndDate = data['registrationEndDate'] != null;
    final registrationEndDate =
        hasRegistrationEndDate
            ? (data['registrationEndDate'] as Timestamp).toDate()
            : null;
    final isRegistrationEnded =
        registrationEndDate != null &&
        DateTime.now().isAfter(registrationEndDate);
    final hasLetter = _letterGenerationStatus[event.id] == true;

    // Process cancelled event to reduce OD count
    if (isCancelled) {
      // Add a button to manually trigger OD count reduction for better user control
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _decrementODCount(event.id);
      });
    }

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
                Expanded(
                  child: Text(
                    data['title'] ?? 'No Title',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: _getStatusTextColor(status),
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
            if (hasRegistrationEndDate)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.timer, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Registration Ends: ${_formatDate(registrationEndDate!)}',
                      style: TextStyle(
                        color: isRegistrationEnded ? Colors.red : null,
                        fontWeight:
                            isRegistrationEnded ? FontWeight.bold : null,
                      ),
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

            // Display letter button if the registration has ended or letter exists
            if ((isRegistrationEnded || hasLetter) && !isCancelled)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ElevatedButton.icon(
                  onPressed:
                      () =>
                          _viewEventLetter(event.id, data['title'] ?? 'Event'),
                  icon: const Icon(Icons.description),
                  label: Text(
                    hasLetter
                        ? 'View Registration Letter'
                        : 'Generate Registration Letter',
                  ),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.orangeAccent,
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ),

            // Display notification about OD count reduction for cancelled events
            if (isCancelled)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        border: Border.all(color: Colors.red[200]!),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.red),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This event has been cancelled. Your OD count will be reduced by 1.',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () => _decrementODCount(event.id),
                      icon: const Icon(Icons.update),
                      label: const Text('Update OD Count'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.red,
                        minimumSize: const Size(double.infinity, 40),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Helper method to get status color
  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green[50]!;
      case 'cancelled':
        return Colors.red[50]!;
      case 'past':
        return Colors.grey[200]!;
      default:
        return Colors.grey[200]!;
    }
  }

  // Helper method to get status text color
  Color _getStatusTextColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'past':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Future<void> _viewEventLetter(String eventId, String eventName) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const Center(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            ),
      );

      // Check if letter exists
      final letterDoc =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('eventLetters')
              .doc(eventId)
              .get();

      // Close loading indicator
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (letterDoc.exists) {
        final letterPath = letterDoc.data()?['letterPath'];
        if (letterPath != null) {
          // Check if file exists
          final file = File(letterPath);
          if (await file.exists()) {
            // Open existing letter
            await OpenFile.open(letterPath);
          } else {
            // Regenerate if file doesn't exist
            _regenerateLetterIfNeeded(eventId, eventName);
          }
        } else {
          // Regenerate if path doesn't exist
          _regenerateLetterIfNeeded(eventId, eventName);
        }
      } else {
        // Generate letter if it doesn't exist
        _regenerateLetterIfNeeded(eventId, eventName);
      }
    } catch (e) {
      debugPrint('Error viewing event letter: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close loading indicator if still shown
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open letter. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _regenerateLetterIfNeeded(
    String eventId,
    String eventName,
  ) async {
    try {
      final eventDoc = await _firestore.collection('events').doc(eventId).get();
      final eventData = eventDoc.data();
      if (eventData != null && eventData['eventDateTime'] != null) {
        await _generateEventLetter(
          eventId,
          eventName,
          (eventData['eventDateTime'] as Timestamp).toDate(),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not generate letter. Event data is missing.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error regenerating letter: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not generate letter. Please try again.'),
          ),
        );
      }
    }
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
          tabs: const [
            Tab(text: 'Active Events'),
            Tab(text: 'Past Events'),
            Tab(text: 'Cancelled Events'),
          ],
        ),
        actions: [
          // Add a button to show current OD count
          StreamBuilder<DocumentSnapshot>(
            stream:
                _firestore
                    .collection('users')
                    .doc(_auth.currentUser?.uid)
                    .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const SizedBox.shrink();
              }

              final userData = snapshot.data?.data() as Map<String, dynamic>?;
              final odCount = userData?['odCount'] ?? 0;

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                margin: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.assignment, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      'OD: $odCount',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(color: Colors.orangeAccent),
              )
              : TabBarView(
                controller: _tabController,
                children: [
                  _buildEventList(_activeEventsStream ?? Stream.value([])),
                  _buildEventList(_pastEventsStream ?? Stream.value([])),
                  _buildEventList(_cancelledEventsStream ?? Stream.value([])),
                ],
              ),
    );
  }

  Widget _buildEventList(Stream<List<DocumentSnapshot>> stream) {
    return StreamBuilder<List<DocumentSnapshot>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.orangeAccent),
          );
        }

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
    return DateFormat('dd/MM/yyyy').format(date);
  }
}
