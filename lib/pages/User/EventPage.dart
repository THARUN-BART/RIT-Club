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
  List<DocumentSnapshot> _followedEvents = [];
  List<String> _followedClubNames = [];
  List<String> _participatedEventIds = []; // Track participated event IDs
  int _odCount = 0; // Track user's OD count
  DateTime? _lastOdResetDate; // Track when OD count was last reset
  String _selectedFilter = "All";
  bool _isLoading = true;
  // Add a map to track user participation status for each event
  Map<String, bool> _participationStatus = {};

  @override
  void initState() {
    super.initState();
    _fetchUserData().then((_) {
      _fetchEvents();
      _checkOdReset(); // Check if OD count needs reset
    });
  }

  // New method to check if OD count needs to be reset (after 3 months)
  Future<void> _checkOdReset() async {
    if (_lastOdResetDate != null) {
      DateTime threeMonthsAgo = DateTime.now().subtract(
        const Duration(days: 90),
      );
      if (_lastOdResetDate!.isBefore(threeMonthsAgo)) {
        // Reset OD count if it's been more than 3 months
        await _resetOdCount();
      }
    }
  }

  // New method to reset OD count
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

        // Apply filter based on current selection
        if (_selectedFilter == "All") {
          _filteredEvents = _events;
        } else if (_selectedFilter == "Following") {
          _filteredEvents =
              _events.where((event) {
                String clubName = event['clubName'] as String;
                return _followedClubNames.contains(clubName);
              }).toList();
        } else {
          // Filter by specific club name
          _filteredEvents =
              _events
                  .where((event) => event['clubName'] == _selectedFilter)
                  .toList();
        }

        // Always populate followed events for the followed section
        _followedEvents =
            _events.where((event) {
              String clubName = event['clubName'] as String;
              return _followedClubNames.contains(clubName);
            }).toList();
      });

      // Check participation status for all events
      await _checkUserParticipation();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Failed to load events: $e');
    }
  }

  // Modified method to check if the user has participated in each event
  Future<void> _checkUserParticipation() async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Initialize participation status map
    Map<String, bool> status = {};

    // Check participation for each event
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

  Future<void> _fetchUserData() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser != null) {
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();

        if (userDoc.exists) {
          // Make sure we're properly retrieving the followedClubNames field
          var followedClubNamesData = userDoc.get('followedClubNames');

          List<String> followedClubNamesList = [];

          // Handle different data types returned from Firestore
          if (followedClubNamesData is List) {
            followedClubNamesList = List<String>.from(
              followedClubNamesData.map((item) => item.toString()),
            );
          } else if (followedClubNamesData is Map) {
            followedClubNamesList = List<String>.from(
              followedClubNamesData.keys,
            );
          }

          // Get participated event IDs
          List<String> participatedEventIdsList = [];
          var participatedEventsData = userDoc.get('participatedEventIds');
          if (participatedEventsData != null) {
            if (participatedEventsData is List) {
              participatedEventIdsList = List<String>.from(
                participatedEventsData.map((item) => item.toString()),
              );
            } else if (participatedEventsData is Map) {
              participatedEventIdsList = List<String>.from(
                participatedEventsData.keys,
              );
            }
          }

          // Get OD count
          int odCount = 0;
          var odCountData = userDoc.get('odCount');
          if (odCountData != null) {
            odCount = odCountData is int ? odCountData : 0;
          }

          // Get last OD reset date
          DateTime? lastOdResetDate;
          var lastOdResetData = userDoc.get('lastOdResetDate');
          if (lastOdResetData != null && lastOdResetData is Timestamp) {
            lastOdResetDate = lastOdResetData.toDate();
          }

          setState(() {
            _followedClubNames = followedClubNamesList;
            _participatedEventIds = participatedEventIdsList;
            _odCount = odCount;
            _lastOdResetDate = lastOdResetDate;
          });
        }
      }
    } catch (e) {
      _showErrorSnackBar('Failed to load user data: $e');
    }
  }

  // The important part is in the _registerForEvent method where we
  // update the user document with the event ID

  Future<void> _registerForEvent(DocumentSnapshot event) async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        _showErrorSnackBar('You must be logged in to register');
        return;
      }

      // Check if registration deadline has passed
      DateTime? registrationDeadline = _parseDateTime(
        event['registrationDateTime'],
      );
      if (registrationDeadline != null &&
          registrationDeadline.isBefore(DateTime.now())) {
        _showErrorSnackBar('Registration deadline has passed');
        return;
      }

      // Get user details from database
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();

      if (!userDoc.exists) {
        _showErrorSnackBar('User profile not found');
        return;
      }

      // Check if user already registered
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

      // Check if user has reached OD limit (3)
      int currentOdCount = 0;
      if (userDoc.data() is Map<String, dynamic>) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        currentOdCount = userData['odCount'] ?? 0;
      }

      if (currentOdCount >= 3) {
        _showErrorSnackBar(
          'You have reached your OD limit (3 events). Please wait for reset after 3 months.',
        );
        return;
      }

      // Show phone number input dialog
      String? phoneNumber = await _showPhoneNumberDialog();
      if (phoneNumber == null) {
        return; // User cancelled the dialog
      }

      // Add registration to participants subcollection of the event
      await _firestore
          .collection('events')
          .doc(event.id)
          .collection('participants')
          .doc(currentUser.uid)
          .set({
            'name': userDoc['name'],
            'regNo': userDoc['regNo'],
            'department': userDoc['department'],
            'phoneNumber': phoneNumber,
            'registeredAt': FieldValue.serverTimestamp(),
          });

      // Update event participants count
      await _firestore.collection('events').doc(event.id).update({
        'participants': FieldValue.increment(1),
      });

      // Get existing participated events from user document
      List<String> participatedEventIds = [];
      if (userDoc.data() is Map<String, dynamic>) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        if (userData['participatedEventIds'] is List) {
          participatedEventIds = List<String>.from(
            userData['participatedEventIds'],
          );
        }
      }

      // Add new event ID to the list if not already there
      if (!participatedEventIds.contains(event.id)) {
        participatedEventIds.add(event.id);
      }

      // Update OD count
      int newOdCount = currentOdCount + 1;

      // Get current time for lastOdResetDate if it doesn't exist
      DateTime now = DateTime.now();
      Timestamp? lastOdResetDate;
      if (userDoc.data() is Map<String, dynamic>) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        if (userData['lastOdResetDate'] is Timestamp) {
          lastOdResetDate = userData['lastOdResetDate'] as Timestamp;
        }
      }

      // Update user document with new event ID and OD count
      await _firestore.collection('users').doc(currentUser.uid).update({
        'participatedEventIds': participatedEventIds,
        'odCount': newOdCount,
        'lastOdResetDate': lastOdResetDate ?? Timestamp.fromDate(now),
      });

      // Update local state
      setState(() {
        _participationStatus[event.id] = true;
        if (_participatedEventIds.contains(event.id) == false) {
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

      if (filter == "All") {
        _filteredEvents = _events;
      } else if (filter == "Following") {
        _filteredEvents =
            _events.where((event) {
              try {
                String clubName = event['clubName'] as String;
                return _followedClubNames.contains(clubName);
              } catch (e) {
                return false;
              }
            }).toList();
      } else {
        // Filter by specific club name
        _filteredEvents =
            _events.where((event) => event['clubName'] == filter).toList();
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
                  ListTile(
                    title: const Text('All Events'),
                    leading: Radio(
                      value: "All",
                      groupValue: _selectedFilter,
                      onChanged: (value) {
                        setModalState(() {
                          _selectedFilter = value as String;
                        });
                        Navigator.pop(context);
                        _filterEvents(value as String);
                      },
                    ),
                  ),
                  ListTile(
                    title: const Text('Followed Clubs Only'),
                    leading: Radio(
                      value: "Following",
                      groupValue: _selectedFilter,
                      onChanged: (value) {
                        setModalState(() {
                          _selectedFilter = value as String;
                        });
                        Navigator.pop(context);
                        _filterEvents(value as String);
                      },
                    ),
                  ),
                  const Divider(),
                  const Text(
                    'Filter by Specific Club',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.start,
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

                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: snapshot.data!.docs.length,
                          itemBuilder: (context, index) {
                            String clubName =
                                snapshot.data!.docs[index]['name'];
                            String clubId = snapshot.data!.docs[index].id;
                            bool isFollowed = _followedClubNames.contains(
                              clubName,
                            );

                            return ListTile(
                              title: Text(clubName),
                              subtitle:
                                  isFollowed
                                      ? const Text(
                                        'Following',
                                        style: TextStyle(color: Colors.green),
                                      )
                                      : null,
                              leading: Radio(
                                value: clubName,
                                groupValue: _selectedFilter,
                                onChanged: (value) {
                                  setModalState(() {
                                    _selectedFilter = value as String;
                                  });
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
          // Add OD count indicator to app bar
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
                    // Followed Clubs Events Section
                    if (_followedEvents.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          "Events from Clubs You Follow",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orangeAccent[700],
                          ),
                        ),
                      ),
                      Container(
                        height: 260,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _followedEvents.length,
                          itemBuilder: (context, index) {
                            DocumentSnapshot event = _followedEvents[index];
                            return SizedBox(
                              width: MediaQuery.of(context).size.width * 0.85,
                              child: EventCard(
                                event: event,
                                onRegister: () => _registerForEvent(event),
                                // Pass participation status to EventCard
                                hasParticipated:
                                    _participationStatus[event.id] ?? false,
                                odCount: _odCount,
                              ),
                            );
                          },
                        ),
                      ),
                      const Divider(thickness: 1, height: 32),
                    ] else if (_followedClubNames.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "The clubs you follow don't have any upcoming events",
                                  style: TextStyle(color: Colors.grey[700]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // All/Filtered Events Section
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        _selectedFilter == "All"
                            ? "All Events"
                            : _selectedFilter == "Following"
                            ? "Events from Clubs You Follow"
                            : "Events from $_selectedFilter",
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
                                if (_selectedFilter == "Following")
                                  Text(
                                    _followedClubNames.isEmpty
                                        ? 'You are not following any clubs'
                                        : 'Followed clubs have no upcoming events',
                                    style: const TextStyle(color: Colors.grey),
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
                              // Pass participation status to EventCard
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
  // Add a new property to track participation status
  final bool hasParticipated;
  // Add a new property to display OD count
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
    // Check if event has reached participant limit
    int participants = event['participants'] ?? 0;
    int participantLimit = event['participantLimit'] ?? 0;
    bool isFull = participantLimit > 0 && participants >= participantLimit;

    DateTime? eventDateTime = _parseDateTime(event['eventDateTime']);
    DateTime? registrationDeadline = _parseDateTime(
      event['registrationDateTime'],
    );

    // Check if registration deadline has passed
    bool isRegistrationClosed =
        registrationDeadline != null &&
        registrationDeadline.isBefore(DateTime.now());

    // Check if user has reached OD limit
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
                    // Show different button based on participation status
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
