import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class EventPage extends StatefulWidget {
  const EventPage({super.key});

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<DocumentSnapshot> _events = [];
  List<DocumentSnapshot> _filteredEvents = [];
  List<String> _followedClubIds = [];
  List<String> _participatedEventIds = [];
  int _odCount = 0;
  DateTime? _lastOdResetDate;
  String _selectedFilter = "";
  bool _isLoading = true;
  Map<String, bool> _participationStatus = {};

  // Add map to store club names
  Map<String, String> _clubNames = {};

  @override
  void initState() {
    super.initState();
    _fetchUserData().then((_) {
      _fetchEvents();
      _checkOdReset();
    });
  }

  Future<void> _checkOdReset() async {
    if (_lastOdResetDate != null) {
      DateTime threeMonthsAgo = DateTime.now().subtract(
        const Duration(days: 90),
      );
      if (_lastOdResetDate!.isBefore(threeMonthsAgo)) {
        await _resetOdCount();
      }
    }
  }

  Future<void> _resetOdCount() async {
    User? currentUser = _auth.currentUser;
    if (currentUser != null) {
      await _firestore.collection('users').doc(currentUser.uid).update({
        'odCount': 0,
        'lastOdResetDate': FieldValue.serverTimestamp(),
      });

      setState(() {
        _odCount = 0;
        _lastOdResetDate = DateTime.now();
      });
    }
  }

  Future<void> _fetchUserData() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser != null) {
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();

        if (userDoc.exists) {
          // Get followed club IDs
          List<String> followedClubIds = [];
          var followedClubsData = userDoc.get('followedClubs');

          if (followedClubsData is List) {
            followedClubIds = List<String>.from(followedClubsData);
          } else if (followedClubsData is Map) {
            followedClubIds = List<String>.from(followedClubsData.keys);
          }

          // Get participated event IDs
          List<String> participatedEventIds = [];
          var participatedEventsData = userDoc.get('participatedEventIds');
          if (participatedEventsData is List) {
            participatedEventIds = List<String>.from(participatedEventsData);
          }

          // Get OD count data
          int odCount = userDoc.get('odCount') ?? 0;
          Timestamp? lastOdResetTimestamp = userDoc.get('lastOdResetDate');
          DateTime? lastOdResetDate = lastOdResetTimestamp?.toDate();

          // Fetch club names
          Map<String, String> clubNames = {};
          QuerySnapshot clubsSnapshot =
              await _firestore.collection('clubs').get();
          for (var doc in clubsSnapshot.docs) {
            clubNames[doc.id] = doc['name'] as String;
          }

          setState(() {
            _followedClubIds = followedClubIds;
            _participatedEventIds = participatedEventIds;
            _odCount = odCount;
            _lastOdResetDate = lastOdResetDate;
            _selectedFilter = "Following"; // Set default filter to Following
            _clubNames = clubNames;
          });
        }
      }
    } catch (e) {
      _showErrorSnackBar('Failed to load user data: $e');
    }
  }

  Future<void> _fetchEvents() async {
    setState(() {
      _isLoading = true;
    });

    try {
      QuerySnapshot eventSnapshot =
          await _firestore
              .collection('events')
              .where('status', isEqualTo: 'active')
              .get();

      setState(() {
        _events = eventSnapshot.docs;
        _applyFilters();
      });

      await _checkUserParticipation();
    } catch (e) {
      _showErrorSnackBar('Failed to load events: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    // Only show events from followed clubs by default
    _filteredEvents =
        _events.where((event) {
          String clubId = event['clubId'] as String;
          return _followedClubIds.contains(clubId);
        }).toList();
  }

  Future<void> _checkUserParticipation() async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) return;

    Map<String, bool> status = {};
    for (var event in _events) {
      try {
        DocumentSnapshot participantDoc =
            await _firestore
                .collection('events')
                .doc(event.id)
                .collection('participants')
                .doc(currentUser.uid)
                .get();

        status[event.id] = participantDoc.exists;
      } catch (e) {
        status[event.id] = false;
      }
    }

    setState(() {
      _participationStatus = status;
    });
  }

  Future<void> _registerForEvent(DocumentSnapshot event) async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        _showErrorSnackBar('You must be logged in to register');
        return;
      }

      DateTime? registrationDeadline = _parseDateTime(
        event['registrationDateTime'],
      );
      if (registrationDeadline != null &&
          registrationDeadline.isBefore(DateTime.now())) {
        _showErrorSnackBar('Registration deadline has passed');
        return;
      }

      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();

      if (!userDoc.exists) {
        _showErrorSnackBar('User profile not found');
        return;
      }

      DocumentSnapshot existingRegistration =
          await _firestore
              .collection('events')
              .doc(event.id)
              .collection('participants')
              .doc(currentUser.uid)
              .get();

      if (existingRegistration.exists) {
        _showErrorSnackBar('You have already registered for this event');
        return;
      }

      int currentOdCount = userDoc.get('odCount') ?? 0;
      if (currentOdCount >= 3) {
        _showErrorSnackBar(
          'You have reached your OD limit (3 events). Please wait for reset after 3 months.',
        );
        return;
      }

      String? phoneNumber = await _showPhoneNumberDialog();
      if (phoneNumber == null) return;

      await _firestore
          .collection('events')
          .doc(event.id)
          .collection('participants')
          .doc(currentUser.uid)
          .set({
            'name': userDoc['name'],
            'regNo': userDoc['regNo'],
            'email': userDoc['email'],
            'department': userDoc['department'],
            'phoneNumber': phoneNumber,
            'Attendance': 'ABSENT',
            'registeredAt': FieldValue.serverTimestamp(),
          });

      await _firestore.collection('events').doc(event.id).update({
        'participants': FieldValue.increment(1),
      });

      List<String> participatedEventIds = List<String>.from(
        userDoc.get('participatedEventIds') ?? [],
      );
      if (!participatedEventIds.contains(event.id)) {
        participatedEventIds.add(event.id);
      }

      int newOdCount = currentOdCount + 1;
      DateTime now = DateTime.now();
      Timestamp? lastOdResetDate = userDoc.get('lastOdResetDate');

      await _firestore.collection('users').doc(currentUser.uid).update({
        'participatedEventIds': participatedEventIds,
        'odCount': newOdCount,
        'lastOdResetDate': lastOdResetDate ?? Timestamp.fromDate(now),
      });

      setState(() {
        _participationStatus[event.id] = true;
        if (!_participatedEventIds.contains(event.id)) {
          _participatedEventIds.add(event.id);
        }
        _odCount = newOdCount;
      });

      _showSuccessSnackBar('Successfully registered for ${event['title']}');
    } catch (e) {
      _showErrorSnackBar('Registration failed: $e');
    }
  }

  Future<String?> _showPhoneNumberDialog() {
    final phoneController = TextEditingController();
    RegExp regExp = RegExp(r'^[6-9]\d{9}$');

    return showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Enter Phone Number'),
            content: TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: 'Phone Number',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                  borderSide: BorderSide(color: Colors.grey, width: 1.0),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  String phoneNumber = phoneController.text.trim();
                  if (regExp.hasMatch(phoneNumber)) {
                    Navigator.pop(context, phoneNumber);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please enter a valid 10-digit phone number starting with 6-9',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('Submit'),
              ),
            ],
          ),
    );
  }

  void _filterEvents(String filter) {
    setState(() {
      _selectedFilter = filter;
      if (filter == "Following") {
        _filteredEvents =
            _events.where((event) {
              String clubId = event['clubId'] as String;
              return _followedClubIds.contains(clubId);
            }).toList();
      } else {
        _filteredEvents =
            _events.where((event) => event['clubId'] == filter).toList();
      }
    });
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Filter Events',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),

                  // Add "All Following Events" option
                  ListTile(
                    title: const Text('All Following Events'),
                    subtitle: const Text(
                      'Show events from all clubs you follow',
                      style: TextStyle(color: Colors.green),
                    ),
                    leading: Radio(
                      value: "Following",
                      groupValue: _selectedFilter,
                      onChanged: (value) {
                        setModalState(() => _selectedFilter = value as String);
                        Navigator.pop(context);
                        _filterEvents(value as String);
                      },
                    ),
                  ),

                  const Divider(),
                  const Text(
                    'Filter by Specific Club',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: FutureBuilder<QuerySnapshot>(
                      future: _firestore.collection('clubs').get(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Center(
                            child: Text('No clubs available'),
                          );
                        }

                        // Filter to only show followed clubs
                        final followedClubs =
                            snapshot.data!.docs.where((doc) {
                              return _followedClubIds.contains(doc.id);
                            }).toList();

                        if (followedClubs.isEmpty) {
                          return const Center(
                            child: Text('You are not following any clubs'),
                          );
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: followedClubs.length,
                          itemBuilder: (context, index) {
                            String clubId = followedClubs[index].id;
                            String clubName = followedClubs[index]['name'];

                            return ListTile(
                              title: Text(clubName),
                              subtitle: const Text(
                                'Following',
                                style: TextStyle(color: Colors.green),
                              ),
                              leading: Radio(
                                value: clubId,
                                groupValue: _selectedFilter,
                                onChanged: (value) {
                                  setModalState(
                                    () => _selectedFilter = value as String,
                                  );
                                  Navigator.pop(context);
                                  _filterEvents(value as String);
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  DateTime? _parseDateTime(dynamic dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr is! String) return null;
    try {
      return DateTime.parse(dateTimeStr);
    } catch (e) {
      return null;
    }
  }

  // Get the club name based on club ID
  String _getClubName(String clubId) {
    return _clubNames[clubId] ?? clubId;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Events",
          style: GoogleFonts.aclonica(fontSize: 25, color: Colors.orangeAccent),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterBottomSheet,
          ),
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _odCount >= 3 ? Colors.red : Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'OD: $_odCount/3',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        _selectedFilter.isEmpty ||
                                _selectedFilter == "Following"
                            ? "Events from Clubs You Follow"
                            : "Events from ${_getClubName(_selectedFilter)}",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _filteredEvents.isEmpty
                        ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.event_busy,
                                  size: 50,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No events available',
                                  style: TextStyle(fontSize: 18),
                                ),
                                if (_followedClubIds.isEmpty)
                                  const Text(
                                    'You are not following any clubs',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                              ],
                            ),
                          ),
                        )
                        : ListView.builder(
                          itemCount: _filteredEvents.length,
                          padding: const EdgeInsets.all(16),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemBuilder: (context, index) {
                            DocumentSnapshot event = _filteredEvents[index];
                            return EventCard(
                              event: event,
                              onRegister: () => _registerForEvent(event),
                              hasParticipated:
                                  _participationStatus[event.id] ?? false,
                              odCount: _odCount,
                            );
                          },
                        ),
                  ],
                ),
              ),
    );
  }
}

class EventCard extends StatelessWidget {
  final DocumentSnapshot event;
  final VoidCallback onRegister;
  final bool hasParticipated;
  final int odCount;

  const EventCard({
    super.key,
    required this.event,
    required this.onRegister,
    required this.hasParticipated,
    required this.odCount,
  });

  @override
  Widget build(BuildContext context) {
    int participants = event['participants'] ?? 0;
    int participantLimit = event['participantLimit'] ?? 0;
    bool isFull = participantLimit > 0 && participants >= participantLimit;

    DateTime? eventDateTime = _parseDateTime(event['eventDateTime']);
    DateTime? registrationDeadline = _parseDateTime(
      event['registrationDateTime'],
    );
    bool isRegistrationClosed =
        registrationDeadline != null &&
        registrationDeadline.isBefore(DateTime.now());
    bool hasReachedOdLimit = odCount >= 3;

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orangeAccent.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.orangeAccent,
                  child: Text(
                    event['clubName'][0],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event['title'],
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        event['clubName'],
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color:
                        event['status'] == 'active' ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    event['status'],
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event['description'],
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      eventDateTime != null
                          ? DateFormat(
                            'MMM dd, yyyy • hh:mm a',
                          ).format(eventDateTime)
                          : 'Date not available',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      event['location'],
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (registrationDeadline != null)
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Registration Deadline: ${DateFormat('MMM dd, yyyy • hh:mm a').format(registrationDeadline)}',
                        style: TextStyle(
                          color:
                              isRegistrationClosed ? Colors.red : Colors.grey,
                          fontWeight:
                              isRegistrationClosed
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${event['participants'] ?? 0}/${event['participantLimit'] ?? "∞"} registered',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isFull ? Colors.red : Colors.blue,
                      ),
                    ),
                    hasParticipated
                        ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Participated',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        )
                        : ElevatedButton(
                          onPressed:
                              (isFull ||
                                      isRegistrationClosed ||
                                      hasReachedOdLimit)
                                  ? null
                                  : onRegister,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(
                            isFull
                                ? 'Event Full'
                                : isRegistrationClosed
                                ? 'Registration Closed'
                                : hasReachedOdLimit
                                ? 'OD Limit Reached'
                                : 'Register',
                          ),
                        ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _parseDateTime(dynamic dateTimeStr) {
    if (dateTimeStr == null || dateTimeStr is! String) return null;
    try {
      return DateTime.parse(dateTimeStr);
    } catch (e) {
      return null;
    }
  }
}
