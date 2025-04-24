import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

class EventPage extends StatefulWidget {
  const EventPage({super.key});

  @override
  State<EventPage> createState() => _EventPageState();
}

class _EventPageState extends State<EventPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  List<DocumentSnapshot> _events = [];
  List<DocumentSnapshot> _filteredEvents = [];
  List<String> _followedClubs = [];
  String _selectedFilter = "Following";
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _fetchUserData().then((_) {
      _fetchEvents(); // Fetch events after we have user data
      _checkAdminStatus(); // Check if user is admin
    });
  }

  Future<void> _fetchEvents() async {
    setState(() {
      _isLoading = true;
    });

    try {
      QuerySnapshot eventSnapshot = await _firestore.collection('events').get();
      setState(() {
        _events = eventSnapshot.docs;
        // Apply the default filter (Following) immediately after loading
        _filteredEvents =
            _events.where((event) {
              String clubId = event['clubId'];
              return _followedClubs.contains(clubId);
            }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Failed to load events: $e');
    }
  }

  Future<void> _fetchUserData() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser != null) {
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();

        if (userDoc.exists) {
          setState(() {
            _followedClubs = List<String>.from(
              userDoc.get('followedClubs') ?? [],
            );
          });
        }
      }
    } catch (e) {
      _showErrorSnackBar('Failed to load user data: $e');
    }
  }

  Future<void> _checkAdminStatus() async {
    try {
      User? currentUser = _auth.currentUser;
      if (currentUser != null) {
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();

        if (userDoc.exists) {
          setState(() {
            _isAdmin = userDoc.get('isAdmin') ?? false;
          });
        }
      }
    } catch (e) {
      _showErrorSnackBar('Failed to check admin status: $e');
    }
  }

  void _filterEvents(String filter) {
    setState(() {
      _selectedFilter = filter;

      if (filter == "All") {
        _filteredEvents = _events;
      } else if (filter == "Following") {
        _filteredEvents =
            _events.where((event) {
              String clubId = event['clubId'];
              return _followedClubs.contains(clubId);
            }).toList();
      } else {
        // Filter by specific club name
        _filteredEvents =
            _events.where((event) => event['clubName'] == filter).toList();
      }
    });
  }

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
      QuerySnapshot existingRegistration =
          await _firestore
              .collection('event_registrations')
              .where('eventId', isEqualTo: event.id)
              .where('userId', isEqualTo: currentUser.uid)
              .get();

      if (existingRegistration.docs.isNotEmpty) {
        _showErrorSnackBar('You have already registered for this event');
        return;
      }

      // Show phone number input dialog
      String? phoneNumber = await _showPhoneNumberDialog();
      if (phoneNumber == null) {
        return; // User cancelled the dialog
      }

      // Add registration to event registrations collection
      await _firestore.collection('event_registrations').add({
        'eventId': event.id,
        'userId': currentUser.uid,
        'name': userDoc['name'],
        'regNo': userDoc['regNo'],
        'department': userDoc['department'],
        'phoneNumber': phoneNumber,
        'registeredAt': FieldValue.serverTimestamp(),
        'offerLetterUrl': null,
      });

      // Update event participants count
      await _firestore.collection('events').doc(event.id).update({
        'participants': FieldValue.increment(1),
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
            title: Text('Enter Phone Number'),
            content: TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: 'Phone Number',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(color: Colors.grey, width: 1.0),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  String phoneNumber = phoneController.text.trim();

                  if (regExp.hasMatch(phoneNumber)) {
                    Navigator.pop(context, phoneNumber);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Please enter a valid 10-digit phone number starting with 6-9',
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: Text('Submit'),
              ),
            ],
          ),
    );
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Filter Events',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  ListTile(
                    title: Text('All Events'),
                    leading: Radio(
                      value: 'All',
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
                    title: Text('Following Clubs'),
                    leading: Radio(
                      value: 'Following',
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
                  Divider(),
                  Expanded(
                    child: FutureBuilder<QuerySnapshot>(
                      future: _firestore.collection('clubs').get(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(child: CircularProgressIndicator());
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return Center(child: Text('No clubs available'));
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: snapshot.data!.docs.length,
                          itemBuilder: (context, index) {
                            String clubName =
                                snapshot.data!.docs[index]['name'];
                            return ListTile(
                              title: Text(clubName),
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

  Future<void> _editEventDateTime(DocumentSnapshot event) async {
    DateTime? currentEventDateTime = _parseDateTime(event['eventDateTime']);
    DateTime? currentRegistrationDateTime = _parseDateTime(
      event['registrationDateTime'],
    );

    final result = await showDialog<Map<String, DateTime?>>(
      context: context,
      builder:
          (context) => DateTimeEditDialog(
            eventDateTime: currentEventDateTime ?? DateTime.now(),
            registrationDeadline: currentRegistrationDateTime ?? DateTime.now(),
          ),
    );

    if (result != null) {
      try {
        await _firestore.collection('events').doc(event.id).update({
          'eventDateTime': result['eventDateTime']!.toIso8601String(),
          'registrationDateTime':
              result['registrationDeadline']!.toIso8601String(),
        });

        _showSuccessSnackBar('Event dates updated successfully');
        _fetchEvents(); // Refresh events
      } catch (e) {
        _showErrorSnackBar('Failed to update event dates: $e');
      }
    }
  }

  Future<void> _showParticipantsAndUploadOfferLetters(
    DocumentSnapshot event,
  ) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(16),
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Event Participants',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                event['title'],
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
              SizedBox(height: 16),
              Text(
                'Upload offer letters after registration deadline has passed',
                style: TextStyle(fontSize: 14, color: Colors.blue),
              ),
              SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<QuerySnapshot>(
                  future:
                      _firestore
                          .collection('event_registrations')
                          .where('eventId', isEqualTo: event.id)
                          .get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(child: Text('No participants yet'));
                    }

                    List<DocumentSnapshot> participants = snapshot.data!.docs;

                    return ListView.builder(
                      itemCount: participants.length,
                      itemBuilder: (context, index) {
                        DocumentSnapshot participant = participants[index];
                        String name = participant['name'] ?? 'Unknown';
                        String regNo = participant['regNo'] ?? 'Unknown';
                        String phone = participant['phoneNumber'] ?? 'Unknown';
                        String? offerLetterUrl = participant['offerLetterUrl'];

                        return Card(
                          margin: EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(name),
                            subtitle: Text('Reg No: $regNo • Phone: $phone'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (offerLetterUrl != null)
                                  IconButton(
                                    icon: Icon(
                                      Icons.remove_red_eye,
                                      color: Colors.blue,
                                    ),
                                    onPressed: () => _viewPdf(offerLetterUrl),
                                    tooltip: 'View Offer Letter',
                                  ),
                                IconButton(
                                  icon: Icon(Icons.upload_file),
                                  onPressed: () async {
                                    DateTime? registrationDeadline =
                                        _parseDateTime(
                                          event['registrationDateTime'],
                                        );
                                    if (registrationDeadline != null &&
                                        registrationDeadline.isAfter(
                                          DateTime.now(),
                                        )) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Cannot upload offer letters until registration deadline passes',
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                      return;
                                    }
                                    await _uploadOfferLetter(participant.id);
                                  },
                                  tooltip: 'Upload Offer Letter',
                                ),
                              ],
                            ),
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
  }

  Future<void> _uploadOfferLetter(String registrationId) async {
    try {
      // Request storage permission
      var status = await Permission.storage.request();
      if (!status.isGranted) {
        _showErrorSnackBar('Storage permission is required');
        return;
      }

      // Pick file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.single.path == null) {
        return;
      }

      File file = File(result.files.single.path!);

      // Show loading indicator
      _showLoadingDialog('Uploading offer letter...');

      // Upload to Firebase Storage
      String fileName =
          'offer_letters/$registrationId-${DateTime.now().millisecondsSinceEpoch}.pdf';
      TaskSnapshot uploadTask = await _storage.ref(fileName).putFile(file);
      String downloadUrl = await uploadTask.ref.getDownloadURL();

      // Update registration in Firestore
      await _firestore
          .collection('event_registrations')
          .doc(registrationId)
          .update({
            'offerLetterUrl': downloadUrl,
            'offerLetterUploadedAt': FieldValue.serverTimestamp(),
          });

      // Hide loading indicator
      Navigator.pop(context);

      _showSuccessSnackBar('Offer letter uploaded successfully');
    } catch (e) {
      // Hide loading if visible
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      _showErrorSnackBar('Failed to upload offer letter: $e');
    }
  }

  Future<void> _viewPdf(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showErrorSnackBar('Could not open PDF');
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text(message),
            ],
          ),
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
            icon: Icon(Icons.filter_list),
            onPressed: _showFilterBottomSheet,
          ),
        ],
      ),
      body:
          _isLoading
              ? Center(child: CircularProgressIndicator())
              : _filteredEvents.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.event_busy, size: 50, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No events available', style: TextStyle(fontSize: 18)),
                    if (_selectedFilter == "Following")
                      Text(
                        'Follow some clubs to see their events',
                        style: TextStyle(color: Colors.grey),
                      ),
                  ],
                ),
              )
              : ListView.builder(
                itemCount: _filteredEvents.length,
                padding: EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  DocumentSnapshot event = _filteredEvents[index];
                  return EventCard(
                    event: event,
                    onRegister: () => _registerForEvent(event),
                    isAdmin: _isAdmin,
                    onEditDateTime:
                        _isAdmin ? () => _editEventDateTime(event) : null,
                    onViewParticipants:
                        _isAdmin
                            ? () =>
                                _showParticipantsAndUploadOfferLetters(event)
                            : null,
                  );
                },
              ),
    );
  }
}

class EventCard extends StatelessWidget {
  final DocumentSnapshot event;
  final VoidCallback onRegister;
  final bool isAdmin;
  final VoidCallback? onEditDateTime;
  final VoidCallback? onViewParticipants;

  const EventCard({
    super.key,
    required this.event,
    required this.onRegister,
    this.isAdmin = false,
    this.onEditDateTime,
    this.onViewParticipants,
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

    return Card(
      elevation: 4,
      margin: EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orangeAccent.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.1),
              borderRadius: BorderRadius.only(
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
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event['title'],
                        style: TextStyle(
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
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        event['status'] == 'active' ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    event['status'],
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event['description'], style: TextStyle(fontSize: 14)),
                SizedBox(height: 16),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      eventDateTime != null
                          ? DateFormat(
                            'MMM dd, yyyy • hh:mm a',
                          ).format(eventDateTime)
                          : 'Date not available',
                      style: TextStyle(color: Colors.grey),
                    ),
                    if (isAdmin && onEditDateTime != null)
                      IconButton(
                        icon: Icon(Icons.edit, size: 16),
                        onPressed: onEditDateTime,
                        tooltip: 'Edit Event Date/Time',
                      ),
                  ],
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: Colors.grey,
                    ),
                    SizedBox(width: 4),
                    Text(
                      event['location'],
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                SizedBox(height: 16),
                if (registrationDeadline != null)
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                      SizedBox(width: 4),
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
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${event['participants'] ?? 0}/${event['participantLimit'] ?? "∞"} registered',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isFull ? Colors.red : Colors.blue,
                          ),
                        ),
                        if (isAdmin && onViewParticipants != null)
                          IconButton(
                            icon: Icon(Icons.people, size: 16),
                            onPressed: onViewParticipants,
                            tooltip: 'View Participants & Upload Offer Letters',
                          ),
                      ],
                    ),
                    ElevatedButton(
                      onPressed:
                          (isFull || isRegistrationClosed) ? null : onRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        isFull
                            ? 'Event Full'
                            : isRegistrationClosed
                            ? 'Registration Closed'
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

class DateTimeEditDialog extends StatefulWidget {
  final DateTime eventDateTime;
  final DateTime registrationDeadline;

  const DateTimeEditDialog({
    super.key,
    required this.eventDateTime,
    required this.registrationDeadline,
  });

  @override
  State<DateTimeEditDialog> createState() => _DateTimeEditDialogState();
}

class _DateTimeEditDialogState extends State<DateTimeEditDialog> {
  late DateTime _eventDateTime;
  late DateTime _registrationDeadline;

  @override
  void initState() {
    super.initState();
    _eventDateTime = widget.eventDateTime;
    _registrationDeadline = widget.registrationDeadline;
  }

  Future<void> _selectEventDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _eventDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(Duration(days: 365)),
    );

    if (picked != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_eventDateTime),
      );

      if (pickedTime != null) {
        setState(() {
          _eventDateTime = DateTime(
            picked.year,
            picked.month,
            picked.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  Future<void> _selectRegistrationDeadline() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _registrationDeadline,
      firstDate: DateTime.now(),
      lastDate: _eventDateTime, // Registration must end before event starts
    );

    if (picked != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_registrationDeadline),
      );

      if (pickedTime != null) {
        setState(() {
          _registrationDeadline = DateTime(
            picked.year,
            picked.month,
            picked.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Event Dates'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Event Date & Time:'),
          InkWell(
            onTap: _selectEventDate,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('MMM dd, yyyy • hh:mm a').format(_eventDateTime),
                  ),
                  Icon(Icons.calendar_today, size: 16),
                ],
              ),
            ),
          ),
          SizedBox(height: 16),
          Text('Registration Deadline:'),
          InkWell(
            onTap: _selectRegistrationDeadline,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat(
                      'MMM dd, yyyy • hh:mm a',
                    ).format(_registrationDeadline),
                  ),
                  Icon(Icons.calendar_today, size: 16),
                ],
              ),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Note: Registration deadline must be before event date',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_registrationDeadline.isAfter(_eventDateTime)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Registration deadline must be before event date',
                  ),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            Navigator.pop(context, {
              'eventDateTime': _eventDateTime,
              'registrationDeadline': _registrationDeadline,
            });
          },
          child: Text('Save'),
        ),
      ],
    );
  }
}

DateTime? _parseDateTime(dynamic dateTimeStr) {
  if (dateTimeStr == null || dateTimeStr is! String) return null;

  try {
    return DateTime.parse(dateTimeStr);
  } catch (e) {
    return null;
  }
}
