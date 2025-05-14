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
  Map<String, bool> _odLetterGenerated = {};
  Map<String, bool> _registrationLetterGenerated = {};
  Map<String, bool> _feedbackSubmitted = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeUserData();
  }

  Future<void> _initializeUserData() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      await _ensureUserFields(userId);
      await _loadUserData(userId);
      await _checkAndGenerateLetters();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error initializing user data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _ensureUserFields(String userId) async {
    final userRef = _firestore.collection('users').doc(userId);
    final userDoc = await userRef.get();

    if (userDoc.exists) {
      final userData = userDoc.data()!;
      final updates = <String, dynamic>{};

      if (!userData.containsKey('odCount')) {
        updates['odCount'] = 0;
      }
      if (!userData.containsKey('processedCancelledEvents')) {
        updates['processedCancelledEvents'] = [];
      }
      if (!userData.containsKey('participatedEventIds')) {
        updates['participatedEventIds'] = [];
      }

      if (updates.isNotEmpty) {
        await userRef.update(updates);
      }
    }
  }

  Future<void> _loadUserData(String userId) async {
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
      });

      await _checkExistingLetters(userId);
      await _checkExistingFeedback(userId);
    }
  }

  Future<void> _checkExistingLetters(String userId) async {
    if (_participatedEventIds.isEmpty) return;

    try {
      final odLetters =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('odLetters')
              .get();

      setState(() {
        for (var doc in odLetters.docs) {
          _odLetterGenerated[doc.id] = true;
        }
      });

      final regLetters =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('registrationLetters')
              .get();

      setState(() {
        for (var doc in regLetters.docs) {
          _registrationLetterGenerated[doc.id] = true;
        }
      });
    } catch (e) {
      debugPrint('Error checking existing letters: $e');
    }
  }

  Future<void> _checkExistingFeedback(String userId) async {
    if (_participatedEventIds.isEmpty) return;

    try {
      final feedback =
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('eventFeedback')
              .get();

      setState(() {
        for (var doc in feedback.docs) {
          _feedbackSubmitted[doc.id] = true;
        }
      });
    } catch (e) {
      debugPrint('Error checking existing feedback: $e');
    }
  }

  Future<void> _checkAndGenerateLetters() async {
    if (_participatedEventIds.isEmpty) return;

    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final now = DateTime.now();

    try {
      final events =
          await _firestore
              .collection('events')
              .where(FieldPath.documentId, whereIn: _participatedEventIds)
              .get();

      for (var event in events.docs) {
        final eventId = event.id;
        final eventName = event['title'] ?? 'Event';
        final eventData = event.data();
        final status = eventData['status']?.toString().toLowerCase() ?? '';

        // Skip cancelled events entirely
        if (status == 'cancelled') continue;

        DateTime? eventDate = _parseDateTime(eventData['eventDateTime']);
        DateTime? regEndDate = _parseDateTime(
          eventData['registrationDateTime'],
        );

        // Generate OD letter if registration period has ended
        if (regEndDate != null && now.isAfter(regEndDate)) {
          if (_odLetterGenerated[eventId] != true) {
            await _generateODLetter(
              eventId,
              eventName,
              regEndDate,
              eventDate!,
              showSnackbar: false,
            );
            setState(() => _odLetterGenerated[eventId] = true);
          }
        }

        // Generate registration letter if event has ended
        if (eventDate != null && now.isAfter(eventDate)) {
          if (_registrationLetterGenerated[eventId] != true) {
            await _generateRegistrationLetter(
              eventId,
              eventName,
              eventDate,
              showSnackbar: false,
            );
            setState(() => _registrationLetterGenerated[eventId] = true);
          }
        }
      }
    } catch (e) {
      debugPrint('Error generating letters: $e');
    }
  }

  DateTime? _parseDateTime(dynamic dateField) {
    if (dateField == null) return null;
    if (dateField is Timestamp) return dateField.toDate();
    if (dateField is String) return DateTime.parse(dateField);
    return null;
  }

  Future<void> _generateODLetter(
    String eventId,
    String eventName,
    DateTime regEndDate,
    DateTime eventDate, {
    bool showSnackbar = true,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null || _currentUserName == null) return;

      final eventDoc = await _firestore.collection('events').doc(eventId).get();
      final eventData = eventDoc.data() ?? {};

      final pdf = pw.Document();
      final formattedDate = DateFormat('dd MMMM yyyy').format(DateTime.now());
      final eventDateFormatted = DateFormat('dd MMMM yyyy').format(eventDate);
      final eventTimeFormatted = DateFormat('hh:mm a').format(eventDate);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Center(
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text(
                          'ON DUTY LETTER',
                          style: pw.TextStyle(
                            fontSize: 30,
                            fontStyle: pw.FontStyle.italic,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(
                          height: 10,
                        ), // Adds spacing between the texts
                        pw.Text(
                          '${eventData['clubName']}',
                          style: pw.TextStyle(fontSize: 20),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(height: 30),
                pw.Container(
                  alignment: pw.Alignment.topRight,
                  child: pw.Text(
                    'Date: $formattedDate',
                    style: pw.TextStyle(fontSize: 12),
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text('From', style: pw.TextStyle(fontSize: 18)),
                pw.SizedBox(height: 10),
                pw.Container(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'President of ${eventData['clubName'] ?? 'our institution'}',
                        style: pw.TextStyle(fontSize: 12),
                      ),
                      pw.Text('RIT CHENNAI'),
                      pw.Text(formattedDate),
                      pw.SizedBox(height: 5),
                    ],
                  ),
                ),
                pw.Text('To,', style: pw.TextStyle(fontSize: 18)),
                pw.SizedBox(height: 10),
                pw.Container(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Dr.Maheswari R,',
                        style: pw.TextStyle(fontSize: 12),
                      ),
                      pw.Text(
                        'Dean of Innovation,',
                        style: pw.TextStyle(fontSize: 12),
                      ),
                      pw.Text('RIT CHENNAI'),
                    ],
                  ),
                ),
                pw.SizedBox(height: 30),
                pw.Text(
                  'Subject: Request for On-Duty Approval for Members during $eventName',
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Respected Dr.Maheswari,',
                  style: pw.TextStyle(fontSize: 18),
                ),
                pw.SizedBox(height: 10),

                pw.Text(
                  'This is to certify that $_currentUserName is officially registered for '
                  'the event "$eventName" organized by ${eventData['clubName'] ?? 'our institution'}. '
                  'The Event is held on $eventDateFormatted at $eventTimeFormatted, '
                  'and it is held on ${eventData['location']}',
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 15),
                pw.Text(
                  'We request you to kindly grant official duty permission to the student '
                  'for participating in this event.',
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 30),
                pw.Text('Yours sincerely,', style: pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 5),
                pw.Text('Event Coordinator', style: pw.TextStyle(fontSize: 12)),
                pw.Text(
                  eventData['clubName'] ?? 'Institution',
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 40),
                pw.Text('Dr.Maheswari,'),
                pw.Text('Signature', style: pw.TextStyle(fontSize: 12)),
              ],
            );
          },
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/OD_Letter_${eventId}_$eventName.pdf';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      try {
        final docRef = _firestore
            .collection('users')
            .doc(userId)
            .collection('odLetters')
            .doc(eventId);

        final docSnapshot = await docRef.get();

        if (docSnapshot.exists) {
          await docRef.update({
            'eventId': eventId,
            'eventName': eventName,
            'generatedDate': Timestamp.now(),
            'filePath': file.path,
          });
        } else {
          await docRef.set({
            'eventId': eventId,
            'eventName': eventName,
            'generatedDate': Timestamp.now(),
            'filePath': file.path,
          });
        }
      } catch (firestoreError) {
        debugPrint('Firestore error in OD letter: $firestoreError');
      }
    } catch (e) {
      debugPrint('Error generating OD letter: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate OD letter: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
    }
  }

  Future<void> _generateRegistrationLetter(
    String eventId,
    String eventName,
    DateTime eventDate, {
    bool showSnackbar = true,
  }) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null || _currentUserName == null) return;

      final eventDoc = await _firestore.collection('events').doc(eventId).get();
      final eventData = eventDoc.data() ?? {};
      final clubName = eventData['clubName'] ?? 'our institution';
      final venue = eventData['location'] ?? 'our campus';

      final pdf = pw.Document();
      final formattedDate = DateFormat('dd MMMM yyyy').format(DateTime.now());
      final eventDateFormatted = DateFormat('dd MMMM yyyy').format(eventDate);
      final eventTimeFormatted = DateFormat('hh:mm a').format(eventDate);

      // Updated Certificate Layout with Digital Signature
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return pw.Container(
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.black, width: 2),
              ),
              child: pw.Container(
                padding: const pw.EdgeInsets.all(15),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColors.black,
                    width: 1,
                    style: pw.BorderStyle.dashed,
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    // Certificate Header
                    pw.Text(
                      'Certificate of Participation',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor(
                          1,
                          0.5,
                          0,
                        ), // RGB values between 0 and 1
                      ),
                    ),

                    pw.SizedBox(height: 15),

                    pw.Text(
                      'This is to certify that',
                      style: pw.TextStyle(fontSize: 14),
                    ),

                    pw.SizedBox(height: 10),

                    // Participant Name
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 5,
                      ),
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(color: PdfColors.black),
                        ),
                      ),
                      child: pw.Text(
                        _currentUserName!,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),

                    pw.SizedBox(height: 20),

                    pw.Text(
                      'has successfully participated in the event',
                      style: pw.TextStyle(fontSize: 14),
                    ),

                    pw.SizedBox(height: 10),

                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: pw.BoxDecoration(
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(4),
                        ),
                        color: PdfColors.grey200,
                      ),
                      child: pw.Text(
                        eventName,
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),

                    pw.SizedBox(height: 15),

                    pw.Text('Organized by', style: pw.TextStyle(fontSize: 14)),
                    pw.SizedBox(height: 5),

                    pw.Text(
                      clubName,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),

                    pw.SizedBox(height: 15),

                    pw.Text(
                      'Date: $eventDateFormatted | Time: $eventTimeFormatted',
                      style: pw.TextStyle(fontSize: 14),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text('Venue: $venue', style: pw.TextStyle(fontSize: 14)),

                    pw.SizedBox(height: 30),

                    // Appreciation message
                    pw.Text(
                      'We sincerely appreciate your dedication and enthusiastic participation. '
                      'Your contributions made this event more meaningful and impactful. '
                      'Thank you for being a part of this journey!',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontStyle: pw.FontStyle.italic,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),

                    // Expand to push signatures to bottom
                    pw.Spacer(),

                    pw.SizedBox(height: 20),

                    // Digital Signature
                    pw.Container(
                      alignment: pw.Alignment.centerRight,
                      padding: const pw.EdgeInsets.only(right: 20),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Container(
                            width: 150,
                            height: 50,
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(
                                color: PdfColors.black,
                                style: pw.BorderStyle.solid,
                              ),
                            ),
                            child: pw.Center(
                              child: pw.Text(
                                'Digitally Signed',
                                style: pw.TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Footer with issue date
                    pw.Container(
                      margin: const pw.EdgeInsets.only(top: 20),
                      alignment: pw.Alignment.centerLeft,
                      child: pw.Text(
                        'Issued on: $formattedDate',
                        style: pw.TextStyle(fontSize: 8),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/Certificate_${eventId}_$eventName.pdf';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      try {
        final docRef = _firestore
            .collection('users')
            .doc(userId)
            .collection('registrationLetters')
            .doc(eventId);

        final docSnapshot = await docRef.get();

        if (docSnapshot.exists) {
          await docRef.update({
            'eventId': eventId,
            'eventName': eventName,
            'generatedDate': Timestamp.now(),
            'filePath': file.path,
          });
        } else {
          await docRef.set({
            'eventId': eventId,
            'eventName': eventName,
            'generatedDate': Timestamp.now(),
            'filePath': file.path,
          });
        }
      } catch (firestoreError) {
        debugPrint('Firestore error in registration letter: $firestoreError');
      }

      if (mounted && showSnackbar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Certificate generated for $eventName'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => OpenFile.open(file.path),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error generating certificate: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate certificate: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      rethrow;
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

  Future<void> _decrementODCount(String eventId) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      await _firestore.runTransaction((transaction) async {
        final userRef = _firestore.collection('users').doc(userId);
        final userDoc = await transaction.get(userRef);

        if (!userDoc.exists) return;

        final userData = userDoc.data()!;
        final currentODCount = userData['odCount'] ?? 0;
        final processedEvents = List<String>.from(
          userData['processedCancelledEvents'] ?? [],
        );

        if (processedEvents.contains(eventId)) return;

        transaction.update(userRef, {
          'odCount': currentODCount > 0 ? currentODCount - 1 : 0,
          'processedCancelledEvents': [...processedEvents, eventId],
        });
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

  Future<void> _submitFeedback(String eventId, String eventName) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    final ratingController = TextEditingController();
    final commentController = TextEditingController();
    int selectedRating = 3;

    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Event Feedback'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Event: $eventName'),
                  const SizedBox(height: 20),
                  const Text('Rate your experience (1-5):'),
                  StatefulBuilder(
                    builder:
                        (context, setState) => Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            5,
                            (index) => IconButton(
                              icon: Icon(
                                index < selectedRating
                                    ? Icons.star
                                    : Icons.star_border,
                                color: Colors.amber,
                              ),
                              onPressed:
                                  () => setState(
                                    () => selectedRating = index + 1,
                                  ),
                            ),
                          ),
                        ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Comments:'),
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Your feedback...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Submit'),
              ),
            ],
          ),
    );

    if (result != true) return;

    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (context) => const Center(child: CircularProgressIndicator()),
        );
      }

      final feedbackData = {
        'eventId': eventId,
        'eventName': eventName,
        'rating': selectedRating,
        'comment': commentController.text.trim(),
        'submittedAt': Timestamp.now(),
        'userName': _currentUserName,
      };

      try {
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('eventFeedback')
            .doc(eventId)
            .set(feedbackData);

        await _firestore
            .collection('events')
            .doc(eventId)
            .collection('feedback')
            .doc(userId)
            .set(feedbackData);

        setState(() => _feedbackSubmitted[eventId] = true);
      } catch (firestoreError) {
        debugPrint('Firestore error in feedback submission: $firestoreError');
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Feedback submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error submitting feedback: $e');
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit feedback: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _viewDocument(
    String collection,
    String eventId,
    String eventName,
  ) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;

    // First check if the event is cancelled and we're trying to view a certificate
    if (collection == 'registrationLetters') {
      final eventDoc = await _firestore.collection('events').doc(eventId).get();
      if (eventDoc.exists &&
          eventDoc.data()?['status']?.toString().toLowerCase() == 'cancelled') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Certificates are not available for cancelled events',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      // 1. First try to find the document in local storage
      String? localFilePath;

      try {
        final doc =
            await _firestore
                .collection('users')
                .doc(userId)
                .collection(collection)
                .doc(eventId)
                .get();

        if (doc.exists && doc.data()?['filePath'] != null) {
          localFilePath = doc.data()?['filePath'] as String;
          final file = File(localFilePath);
          if (await file.exists()) {
            if (mounted) {
              Navigator.of(context).pop();
              await OpenFile.open(localFilePath);
              return;
            }
          }
        }
      } catch (firestoreError) {
        debugPrint(
          'Firestore error when trying to get document: $firestoreError',
        );
      }

      // 2. If not found locally, generate it
      final event = await _firestore.collection('events').doc(eventId).get();
      if (!event.exists) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Event data not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final eventData = event.data()!;

      if (collection == 'odLetters') {
        final regEndDate = _parseDateTime(eventData['registrationDateTime']);
        final eventDateTime = _parseDateTime(eventData['eventDateTime']);
        if (regEndDate != null) {
          await _generateODLetter(
            eventId,
            eventName,
            regEndDate,
            eventDateTime!,
          );
          setState(() => _odLetterGenerated[eventId] = true);
        }
      } else {
        final eventDateTime = _parseDateTime(eventData['eventDateTime']);
        if (eventDateTime != null) {
          await _generateRegistrationLetter(eventId, eventName, eventDateTime);
          setState(() => _registrationLetterGenerated[eventId] = true);
        }
      }

      // 3. Try to open the newly created file
      final dir = await getApplicationDocumentsDirectory();
      final expectedFilePath =
          collection == 'odLetters'
              ? '${dir.path}/OD_Letter_${eventId}_$eventName.pdf'
              : '${dir.path}/Certificate_${eventId}_$eventName.pdf';

      final file = File(expectedFilePath);
      if (await file.exists()) {
        if (mounted) {
          Navigator.of(context).pop();
          await OpenFile.open(expectedFilePath);
        }
      } else {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not find the generated document'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error viewing document: $e');
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open document: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _getParticipantData(String eventId) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return null;

      final participantDoc =
          await _firestore
              .collection('events')
              .doc(eventId)
              .collection('participants')
              .doc(userId)
              .get();

      return participantDoc.data();
    } catch (e) {
      debugPrint('Error fetching participant data: $e');
      return null;
    }
  }

  Widget _buildEventCard(DocumentSnapshot event) {
    final data = event.data() as Map<String, dynamic>;
    final eventId = event.id;
    final eventName = data['title'] ?? 'Event';
    final status = data['status']?.toString().toLowerCase() ?? '';
    final isCancelled = status == 'cancelled';
    final isPast = status == 'past';

    // Parse dates
    final eventDate = _parseDateTime(data['eventDateTime']);
    final regEndDate = _parseDateTime(data['registrationDateTime']);
    final now = DateTime.now();

    // Determine states
    final isRegEnded = regEndDate != null && now.isAfter(regEndDate);
    final isEventEnded = eventDate != null && now.isAfter(eventDate) || isPast;
    final hasODLetter = _odLetterGenerated[eventId] == true;
    final hasRegLetter = _registrationLetterGenerated[eventId] == true;
    final hasFeedback = _feedbackSubmitted[eventId] == true;

    return FutureBuilder<Map<String, dynamic>?>(
      future: _getParticipantData(eventId),
      builder: (context, participantSnapshot) {
        String participantStatus = 'unknown';
        bool isPresent = false;
        String? participantName;
        DateTime? attendanceUpdatedAt;

        if (participantSnapshot.connectionState == ConnectionState.done &&
            participantSnapshot.hasData &&
            participantSnapshot.data != null) {
          final participantData = participantSnapshot.data!;
          participantStatus =
              participantData['Attendance']?.toString().toLowerCase() ??
              'unknown';
          isPresent = participantStatus == 'present';
          participantName = participantData['name']?.toString();

          // Parse attendance update timestamp if available
          if (participantData['attendanceUpdateAt'] != null) {
            attendanceUpdatedAt = _parseDateTime(
              participantData['attendanceUpdateAt'],
            );
          }
        }

        // Handle cancelled events silently
        if (isCancelled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _decrementODCount(eventId);
          });
        }

        return Card(
          margin: const EdgeInsets.all(8),
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
                        eventName,
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
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (isCancelled)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'This event has been cancelled',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                if (participantName != null)
                  _buildInfoRow(
                    Icons.person,
                    'Registered as: $participantName',
                  ),
                if (data['description'] != null)
                  _buildInfoRow(Icons.description, data['description']!),
                if (eventDate != null)
                  _buildInfoRow(
                    Icons.calendar_today,
                    DateFormat('EEE, MMM d, yyyy • hh:mm a').format(eventDate),
                  ),
                if (regEndDate != null)
                  _buildInfoRow(
                    Icons.timer,
                    'Registration ends: ${DateFormat('MMM d, yyyy').format(regEndDate)}',
                  ),
                if (data['clubName'] != null)
                  _buildInfoRow(Icons.group, 'By: ${data['clubName']}'),
                if (data['venue'] != null)
                  _buildInfoRow(Icons.location_on, data['venue']),
                // Show attendance status if available
                if (participantStatus != 'unknown')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow(
                        isPresent ? Icons.check_circle : Icons.cancel,
                        'Attendance: ${participantStatus.toUpperCase()}',
                        color: isPresent ? Colors.green : Colors.red,
                      ),
                      if (attendanceUpdatedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: Text(
                            'Marked on: ${DateFormat('MMM d, yyyy hh:mm a').format(attendanceUpdatedAt!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Show OD Letter button if registration has ended and event is not cancelled
                    if (isRegEnded && !isCancelled)
                      _buildActionButton(
                        'OD Letter',
                        Icons.description,
                        hasODLetter ? Colors.green : Colors.blue,
                        () => _viewDocument('odLetters', eventId, eventName),
                      ),

                    // Show Certificate button for past events or ended events with present attendance
                    if ((isEventEnded || isPast) && !isCancelled && isPresent)
                      _buildActionButton(
                        'Certificate',
                        Icons.card_membership,
                        hasRegLetter ? Colors.green : Colors.blue,
                        () => _viewDocument(
                          'registrationLetters',
                          eventId,
                          eventName,
                        ),
                      ),

                    // Show Feedback button for past events or ended events with present attendance
                    if ((isEventEnded || isPast) &&
                        !isCancelled &&
                        isPresent &&
                        !hasFeedback)
                      _buildActionButton(
                        'Feedback',
                        Icons.feedback,
                        Colors.orange,
                        () => _submitFeedback(eventId, eventName),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Updated _buildInfoRow to support custom colors
  Widget _buildInfoRow(IconData icon, String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color ?? Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: color),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 16),
        label: Text(label),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green.shade100;
      case 'past':
        return Colors.blue.shade100;
      case 'cancelled':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  Color _getStatusTextColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green.shade800;
      case 'past':
        return Colors.blue.shade800;
      case 'cancelled':
        return Colors.red.shade800;
      default:
        return Colors.grey.shade800;
    }
  }

  Widget _buildEventsContent(Stream<List<DocumentSnapshot>> eventsStream) {
    return StreamBuilder<List<DocumentSnapshot>>(
      stream: eventsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final events = snapshot.data ?? [];
        if (events.isEmpty) {
          return const Center(
            child: Text(
              'No events found',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          itemCount: events.length,
          itemBuilder: (context, index) => _buildEventCard(events[index]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My Events',
          style: GoogleFonts.aclonica(fontSize: 25, color: Colors.orangeAccent),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Past'),
            Tab(text: 'Cancelled'),
          ],
          labelColor: Colors.orangeAccent,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orangeAccent,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEventsContent(_activeEventsStream!),
          _buildEventsContent(_pastEventsStream!),
          _buildEventsContent(_cancelledEventsStream!),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}
