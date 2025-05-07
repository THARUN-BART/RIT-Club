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
  String _selectedFilter = "Following";
  bool _isLoading = true;
  Map<String, bool> _participationStatus = {};
  Map<String, String> _clubNames = {};
  Map<String, Map<String, dynamic>> _teamInvitations = {};

  @override
  void initState() {
    super.initState();
    _fetchUserData().then((_) {
      _fetchEvents();
      _checkOdReset();
      _fetchTeamInvitations();
    });
  }

  Future<void> _fetchTeamInvitations() async {
    User? user = _auth.currentUser;
    if (user == null) return;

    DocumentSnapshot userDoc =
        await _firestore.collection('users').doc(user.uid).get();
    if (userDoc.exists) {
      setState(() {
        _teamInvitations = Map<String, Map<String, dynamic>>.from(
          userDoc['eventInvitations'] ?? {},
        );
      });
    }
  }

  Future<void> _handleInvitationResponse(
    String eventId,
    String teamId,
    bool accept,
  ) async {
    User? user = _auth.currentUser;
    if (user == null) return;

    try {
      WriteBatch batch = _firestore.batch();

      // Update user's invitation status
      batch.update(_firestore.collection('users').doc(user.uid), {
        'eventInvitations.$eventId.status': accept ? 'accepted' : 'rejected',
      });

      if (accept) {
        // Get the event document to check the teams
        DocumentSnapshot eventDoc =
            await _firestore.collection('events').doc(eventId).get();

        if (!eventDoc.exists) {
          throw Exception('Event not found');
        }

        List<dynamic> teams = eventDoc['teams'] ?? [];

        // Find the team with matching teamId
        var teamIndex = teams.indexWhere((t) => t['teamId'] == teamId);

        if (teamIndex == -1) {
          throw Exception('Team not found in event');
        }

        // Make a copy of the teams to update
        List<dynamic> updatedTeams = List.from(teams);

        // Get members from the team
        List<dynamic> members = updatedTeams[teamIndex]['members'] ?? [];

        // Add user email if not already in members
        if (!members.contains(user.email)) {
          members = List.from(members)..add(user.email);
          updatedTeams[teamIndex]['members'] = members;
        }

        // Update the teams field in the event document
        batch.update(_firestore.collection('events').doc(eventId), {
          'teams': updatedTeams,
        });
      }

      await batch.commit();

      if (accept) {
        await _checkTeamCompletion(eventId, teamId);
      }

      setState(() {
        if (_teamInvitations.containsKey(eventId)) {
          _teamInvitations.remove(eventId);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept ? 'Invitation accepted!' : 'Invitation declined',
          ),
          backgroundColor: accept ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to respond: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _checkTeamCompletion(String eventId, String teamId) async {
    try {
      DocumentSnapshot eventDoc =
          await _firestore.collection('events').doc(eventId).get();
      if (!eventDoc.exists) return;

      List<dynamic> teams = eventDoc['teams'] ?? [];

      // Check if teams is empty before trying to access elements
      if (teams.isEmpty) {
        debugPrint('No teams found for event $eventId');
        return;
      }

      // Use firstWhere with orElse that returns null instead of throwing an error
      var team = teams.firstWhere(
        (t) => t['teamId'] == teamId,
        orElse: () => null,
      );

      // Check if team is null before proceeding
      if (team == null) {
        debugPrint('Team $teamId not found in event $eventId');
        return;
      }

      // Ensure members exists and is not empty
      List<String> members = [];
      if (team['members'] != null && team['members'] is List) {
        members = List<String>.from(team['members']);
      }

      if (members.isEmpty) {
        debugPrint('No members found for team $teamId in event $eventId');
        return;
      }

      bool allAccepted = true;
      for (String memberEmail in members) {
        QuerySnapshot userQuery =
            await _firestore
                .collection('users')
                .where('email', isEqualTo: memberEmail)
                .limit(1)
                .get();

        if (userQuery.docs.isEmpty) {
          allAccepted = false;
          break;
        }

        var userDoc = userQuery.docs.first;
        var eventInvitations = userDoc.data() as Map<String, dynamic>;

        // Safely access nested maps with null checks
        if (eventInvitations['eventInvitations'] == null ||
            eventInvitations['eventInvitations'][eventId] == null ||
            eventInvitations['eventInvitations'][eventId]['status'] !=
                'accepted') {
          allAccepted = false;
          break;
        }
      }

      if (allAccepted) {
        WriteBatch batch = _firestore.batch();

        var updatedTeams =
            teams
                .map(
                  (t) =>
                      t['teamId'] == teamId ? {...t, 'status': 'accepted'} : t,
                )
                .toList();

        batch.update(_firestore.collection('events').doc(eventId), {
          'teams': updatedTeams,
          'participants': FieldValue.increment(members.length),
        });

        for (String memberEmail in members) {
          QuerySnapshot userQuery =
              await _firestore
                  .collection('users')
                  .where('email', isEqualTo: memberEmail)
                  .limit(1)
                  .get();

          if (userQuery.docs.isNotEmpty) {
            batch.update(userQuery.docs.first.reference, {
              'odCount': FieldValue.increment(1),
              'participatedEventIds': FieldValue.arrayUnion([eventId]),
            });
          }
        }

        await batch.commit();

        setState(() {
          _odCount += 1;
          if (!_participatedEventIds.contains(eventId)) {
            _participatedEventIds.add(eventId);
          }
        });
      }
    } catch (e) {
      debugPrint('Error checking team completion: $e');
    }
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
          List<String> followedClubIds = [];
          var followedClubsData = userDoc.get('followedClubs');
          if (followedClubsData is List) {
            followedClubIds = List<String>.from(followedClubsData);
          } else if (followedClubsData is Map) {
            followedClubIds = List<String>.from(followedClubsData.keys);
          }

          List<String> participatedEventIds = [];
          var participatedEventsData = userDoc.get('participatedEventIds');
          if (participatedEventsData is List) {
            participatedEventIds = List<String>.from(participatedEventsData);
          }

          int odCount = userDoc.get('odCount') ?? 0;
          Timestamp? lastOdResetTimestamp = userDoc.get('lastOdResetDate');
          DateTime? lastOdResetDate = lastOdResetTimestamp?.toDate();

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
            _clubNames = clubNames;
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load user data: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load events: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
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
        bool isTeamEvent = event['isTeamEvent'] ?? false;
        if (isTeamEvent) {
          List<dynamic> teams = event['teams'] ?? [];
          bool isInTeam = teams.any((team) {
            List<String> members = List<String>.from(team['members'] ?? []);
            return members.contains(currentUser.email);
          });
          status[event.id] = isInTeam;
        } else {
          DocumentSnapshot participantDoc =
              await _firestore
                  .collection('events')
                  .doc(event.id)
                  .collection('participants')
                  .doc(currentUser.uid)
                  .get();
          status[event.id] = participantDoc.exists;
        }
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to register')),
        );
        return;
      }

      bool isTeamEvent = event['isTeamEvent'] ?? false;
      if (isTeamEvent) {
        await _registerTeam(event);
      } else {
        await _registerIndividual(event);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Registration failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _registerTeam(DocumentSnapshot event) async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Check registration deadline
    DateTime? registrationDeadline = _parseDateTime(
      event['registrationDateTime'],
    );
    if (registrationDeadline != null &&
        registrationDeadline.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration deadline has passed')),
      );
      return;
    }

    // Check if already registered
    if (_participationStatus[event.id] ?? false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have already registered for this event'),
        ),
      );
      return;
    }

    // Check OD count
    DocumentSnapshot userDoc =
        await _firestore.collection('users').doc(currentUser.uid).get();
    int currentOdCount = userDoc['odCount'] ?? 0;
    if (currentOdCount >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have reached your OD limit (3 events)'),
        ),
      );
      return;
    }

    // Show team registration dialog
    Map<String, dynamic>? teamData = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (context) => TeamRegistrationDialog(
            teamSize:
                event['teamSize'] is int && event['teamSize'] > 0
                    ? event['teamSize']
                    : 2,
          ),
    );

    // Check if user cancelled the dialog
    if (teamData == null) return;

    // Create team with pending status
    String teamId = _firestore.collection('events').doc().id;

    Map<String, dynamic> teamObject = {
      'teamId': teamId,
      'teamName': teamData['teamName'],
      'captain': currentUser.email,
      'members': [currentUser.email],
      'status': 'pending',
      'createdAt': Timestamp.now(),
    };

    await _firestore.collection('events').doc(event.id).update({
      'teams': FieldValue.arrayUnion([teamObject]),
    });

    // Send invitations to team members
    WriteBatch batch = _firestore.batch();

    // Ensure team members is a valid list before proceeding
    List<String> memberEmails = [];
    if (teamData['members'] != null && teamData['members'] is List) {
      memberEmails = List<String>.from(teamData['members']);
    }

    for (String memberEmail in memberEmails) {
      if (memberEmail != currentUser.email) {
        QuerySnapshot userQuery =
            await _firestore
                .collection('users')
                .where('email', isEqualTo: memberEmail)
                .limit(1)
                .get();

        if (userQuery.docs.isNotEmpty) {
          Map<String, dynamic> invitation = {
            'teamId': teamId,
            'status': 'pending',
            'invitedAt': Timestamp.now(),
            'eventTitle': event['title'] ?? 'Untitled Event',
            'teamName': teamData['teamName'],
          };

          batch.update(userQuery.docs.first.reference, {
            'eventInvitations.${event.id}': invitation,
          });
        }
      }
    }

    await batch.commit();

    // Update local state
    setState(() {
      _participationStatus[event.id] = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Team created! Invitations sent to members'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _registerIndividual(DocumentSnapshot event) async {
    User? currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Check registration deadline
    DateTime? registrationDeadline = _parseDateTime(
      event['registrationDateTime'],
    );
    if (registrationDeadline != null &&
        registrationDeadline.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration deadline has passed')),
      );
      return;
    }

    // Check if already registered
    if (_participationStatus[event.id] ?? false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have already registered for this event'),
        ),
      );
      return;
    }

    // Check OD count
    DocumentSnapshot userDoc =
        await _firestore.collection('users').doc(currentUser.uid).get();
    int currentOdCount = userDoc['odCount'] ?? 0;
    if (currentOdCount >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have reached your OD limit (3 events)'),
        ),
      );
      return;
    }

    // Get phone number
    String? phoneNumber = await _showPhoneNumberDialog();
    if (phoneNumber == null) return;

    // Register for event
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
          'registeredAt': Timestamp.now(),
        });

    await _firestore.collection('events').doc(event.id).update({
      'participants': FieldValue.increment(1),
    });

    // Update user's OD count
    await _firestore.collection('users').doc(currentUser.uid).update({
      'odCount': FieldValue.increment(1),
      'participatedEventIds': FieldValue.arrayUnion([event.id]),
      'lastOdResetDate': userDoc['lastOdResetDate'] ?? Timestamp.now(),
    });

    // Update local state
    setState(() {
      _participationStatus[event.id] = true;
      _odCount = currentOdCount + 1;
      if (!_participatedEventIds.contains(event.id)) {
        _participatedEventIds.add(event.id);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Successfully registered for ${event['title']}'),
        backgroundColor: Colors.green,
      ),
    );
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
              : Column(
                children: [
                  if (_teamInvitations.isNotEmpty)
                    ExpansionTile(
                      title: Text(
                        'Team Invitations (${_teamInvitations.length})',
                      ),
                      initiallyExpanded: true,
                      children:
                          _teamInvitations.entries.map((entry) {
                            var invitation = entry.value;
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: ListTile(
                                title: Text(invitation['teamName']),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(invitation['eventTitle']),
                                    const Text('Team invitation'),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.check,
                                        color: Colors.green,
                                      ),
                                      onPressed:
                                          () => _handleInvitationResponse(
                                            entry.key,
                                            invitation['teamId'],
                                            true,
                                          ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.red,
                                      ),
                                      onPressed:
                                          () => _handleInvitationResponse(
                                            entry.key,
                                            invitation['teamId'],
                                            false,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  Expanded(
                    child:
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
                              itemBuilder: (context, index) {
                                DocumentSnapshot event = _filteredEvents[index];
                                bool isTeamEvent =
                                    event['isTeamEvent'] ?? false;
                                bool hasParticipated =
                                    _participationStatus[event.id] ?? false;
                                bool isTeamCaptain =
                                    isTeamEvent &&
                                    (event['teams'] as List).any(
                                      (team) =>
                                          team['captain'] ==
                                              _auth.currentUser?.email &&
                                          team['members'].contains(
                                            _auth.currentUser?.email,
                                          ),
                                    );

                                return EventCard(
                                  event: event,
                                  onRegister: () => _registerForEvent(event),
                                  hasParticipated: hasParticipated,
                                  isTeamEvent: isTeamEvent,
                                  isTeamCaptain: isTeamCaptain,
                                );
                              },
                            ),
                  ),
                ],
              ),
    );
  }
}

class TeamRegistrationDialog extends StatefulWidget {
  final int teamSize;

  const TeamRegistrationDialog({Key? key, required this.teamSize})
    : super(key: key);

  @override
  State<TeamRegistrationDialog> createState() => _TeamRegistrationDialogState();
}

class _TeamRegistrationDialogState extends State<TeamRegistrationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _teamNameController = TextEditingController();
  final List<TextEditingController> _memberControllers = [];
  final List<Map<String, dynamic>?> _memberDetails = [];
  final List<bool> _isValidating = [];
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    // Ensure teamSize is at least 1, and calculate the number of additional members needed
    int additionalMembers = (widget.teamSize > 1) ? widget.teamSize - 1 : 1;

    // Initialize controllers for each team member slot
    for (int i = 0; i < additionalMembers; i++) {
      _memberControllers.add(TextEditingController());
      _memberDetails.add(null);
      _isValidating.add(false);
    }
  }

  @override
  void dispose() {
    _teamNameController.dispose();
    for (var controller in _memberControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _validateMemberEmail(int index) async {
    final email = _memberControllers[index].text.trim();
    final emailRegex = RegExp(r'^[a-z]+\.[0-9]+@[a-z]+\.ritchennai\.edu\.in$');

    if (!emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please use format: abc.123456@dept.ritchennai.edu.in'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _memberDetails[index] = null);
      return;
    }

    setState(() {
      _isValidating[index] = true;
      _memberDetails[index] = null;
    });

    try {
      final userQuery =
          await _firestore
              .collection('users')
              .where('email', isEqualTo: email)
              .limit(1)
              .get();

      if (userQuery.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User $email not found in system'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final userData = userQuery.docs.first.data();
      setState(() {
        _memberDetails[index] = {
          'name': userData['name'] ?? 'Unknown',
          'regNo': userData['regNo'] ?? 'N/A',
          'department': userData['department'] ?? 'Not specified',
        };
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error validating user: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isValidating[index] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserEmail = FirebaseAuth.instance.currentUser?.email ?? '';

    return AlertDialog(
      title: const Text('Register Team'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Team Name Field
              TextFormField(
                controller: _teamNameController,
                decoration: const InputDecoration(
                  labelText: 'Team Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.group),
                ),
                validator:
                    (value) =>
                        value == null || value.isEmpty
                            ? 'Please enter a team name'
                            : null,
              ),
              const SizedBox(height: 16),

              // Team Captain Info
              const Text(
                'Team Captain:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(currentUserEmail),
                subtitle: const Text('You (Team Captain)'),
              ),
              const Divider(),

              // Team Members Section
              const Text(
                'Team Members:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter valid institute emails (abc.123456@dept.ritchennai.edu.in)',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),

              // Member Input Fields - Check if there are any controllers
              if (_memberControllers.isNotEmpty)
                for (int i = 0; i < _memberControllers.length; i++) ...[
                  _buildMemberInputField(i, currentUserEmail),
                  if (_memberDetails[i] != null) _buildMemberDetailsCard(i),
                  const SizedBox(height: 8),
                ]
              else
                const Text("No additional members needed for this team."),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submitForm,
          child: const Text('Create Team'),
        ),
      ],
    );
  }

  Widget _buildMemberInputField(int index, String currentUserEmail) {
    return TextFormField(
      controller: _memberControllers[index],
      decoration: InputDecoration(
        labelText: 'Team Member ${index + 1}',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.email),
        suffixIcon: IconButton(
          icon:
              _isValidating[index]
                  ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.verified_user),
          onPressed: () => _validateMemberEmail(index),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Please enter member email';
        if (!RegExp(
          r'^[a-z]+\.[0-9]+@[a-z]+\.ritchennai\.edu\.in$',
        ).hasMatch(value)) {
          return 'Invalid institute email format';
        }
        if (value == currentUserEmail) return 'Cannot add yourself as member';
        for (int j = 0; j < _memberControllers.length; j++) {
          if (index != j && _memberControllers[j].text == value) {
            return 'Duplicate email address';
          }
        }
        if (_memberDetails[index] == null) return 'Please verify this email';
        return null;
      },
    );
  }

  Widget _buildMemberDetailsCard(int index) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${_memberDetails[index]!['name']}'),
            Text('Reg No: ${_memberDetails[index]!['regNo']}'),
            Text('Department: ${_memberDetails[index]!['department']}'),
          ],
        ),
      ),
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    // Make sure all members are verified
    for (int i = 0; i < _memberControllers.length; i++) {
      if (_memberDetails[i] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please verify member ${i + 1} email'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // Collect member emails
    List<String> memberEmails = [currentUser.email!];
    for (var controller in _memberControllers) {
      if (controller.text.trim().isNotEmpty) {
        memberEmails.add(controller.text.trim());
      }
    }

    Navigator.pop(context, {
      'teamName': _teamNameController.text.trim(),
      'members': memberEmails,
    });
  }
}

class EventCard extends StatelessWidget {
  final DocumentSnapshot event;
  final VoidCallback onRegister;
  final bool hasParticipated;
  final bool isTeamEvent;
  final bool isTeamCaptain;

  const EventCard({
    required this.event,
    required this.onRegister,
    required this.hasParticipated,
    required this.isTeamEvent,
    required this.isTeamCaptain,
    super.key,
  });

  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return 'TBA';
    try {
      DateTime dateTime = DateTime.parse(dateTimeStr);
      return DateFormat('MMM dd, yyyy • hh:mm a').format(dateTime);
    } catch (e) {
      return 'Invalid date';
    }
  }

  bool get isRegistrationOpen {
    try {
      if (event['registrationDateTime'] == null) return false;
      DateTime registrationDeadline = DateTime.parse(
        event['registrationDateTime'],
      );
      return registrationDeadline.isAfter(DateTime.now());
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event Title and Club
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.orange.shade100,
                  child: Icon(
                    isTeamEvent ? Icons.group : Icons.person,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event['title']?.toString() ?? 'Event',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        event['clubName']?.toString() ?? 'Club',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Event Description
            Text(
              event['description']?.toString() ?? 'No description provided',
              style: const TextStyle(fontSize: 15),
            ),

            const SizedBox(height: 16),

            // Event Details
            _buildDetailRow(
              Icons.calendar_today,
              _formatDateTime(event['eventDateTime']?.toString()),
            ),
            _buildDetailRow(
              Icons.location_on,
              event['location']?.toString() ?? 'TBA',
            ),
            _buildDetailRow(
              Icons.access_time,
              'Reg. Deadline: ${_formatDateTime(event['registrationDateTime']?.toString())}',
              isClosed: !isRegistrationOpen,
            ),

            if (isTeamEvent)
              _buildDetailRow(
                Icons.people,
                'Team Size: ${event['teamSize']?.toString() ?? '2'} members',
              ),

            const SizedBox(height: 16),

            // Button aligned to bottom right
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 180, // Fixed width for consistent sizing
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          hasParticipated
                              ? Colors.grey
                              : isRegistrationOpen
                              ? Colors.orange
                              : Colors.red,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed:
                        isRegistrationOpen && !hasParticipated
                            ? onRegister
                            : null,
                    child: Text(
                      hasParticipated
                          ? 'Registered ✓'
                          : isRegistrationOpen
                          ? isTeamEvent
                              ? 'Register Team'
                              : 'Register Now'
                          : 'Registration Closed',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Team Captain badge
            if (isTeamEvent && isTeamCaptain)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Team Captain',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text, {bool isClosed = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: isClosed ? Colors.red : Colors.grey),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: isClosed ? Colors.red : Colors.grey,
              fontSize: 14,
              fontWeight: isClosed ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
