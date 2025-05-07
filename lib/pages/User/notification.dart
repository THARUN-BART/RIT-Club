import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class EventNotification extends StatefulWidget {
  const EventNotification({super.key});

  @override
  State<EventNotification> createState() => _EventNotificationState();
}

class _EventNotificationState extends State<EventNotification> {
  final User? user = FirebaseAuth.instance.currentUser;
  List<Map<String, dynamic>> _pendingEvents = [];
  List<Map<String, dynamic>> _teamInvitations = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    if (user == null) {
      setState(() {
        _isLoading = false;
        _pendingEvents = [];
        _teamInvitations = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      DocumentSnapshot userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user!.uid)
              .get();

      if (!userDoc.exists) {
        setState(() {
          _isLoading = false;
          _pendingEvents = [];
          _teamInvitations = [];
        });
        return;
      }

      // 1. Get team invitations
      Map<String, dynamic>? invitations = userDoc['eventInvitations'];
      List<Map<String, dynamic>> teamInvites = [];

      if (invitations != null) {
        invitations.forEach((eventId, inviteData) {
          if (inviteData['status'] == 'pending') {
            teamInvites.add({
              'eventId': eventId,
              'teamId': inviteData['teamId'],
              'eventTitle': inviteData['eventTitle'],
              'teamName': inviteData['teamName'],
              'invitedAt': (inviteData['invitedAt'] as Timestamp).toDate(),
            });
          }
        });
      }

      // 2. Get individual event invitations
      List<Map<String, dynamic>> pendingEvents = [];
      List<String> followedClubs = List<String>.from(
        userDoc['followedClubs'] ?? [],
      );

      if (followedClubs.isNotEmpty) {
        for (String clubId in followedClubs) {
          QuerySnapshot eventsSnapshot =
              await FirebaseFirestore.instance
                  .collection('clubs')
                  .doc(clubId)
                  .collection('events')
                  .where('status', isEqualTo: 'active')
                  .where('eventDate', isGreaterThan: Timestamp.now())
                  .get();

          for (var eventDoc in eventsSnapshot.docs) {
            Map<String, dynamic> eventData =
                eventDoc.data() as Map<String, dynamic>;
            Map<String, dynamic> responses = eventData['responses'] ?? {};

            if (!responses.containsKey(user!.email)) {
              DocumentSnapshot clubDoc =
                  await FirebaseFirestore.instance
                      .collection('clubs')
                      .doc(clubId)
                      .get();

              pendingEvents.add({
                'id': eventDoc.id,
                'clubId': clubId,
                'clubName': clubDoc['name'] ?? 'Unknown Club',
                'title': eventData['title'] ?? 'No title',
                'description': eventData['description'] ?? 'No description',
                'location': eventData['location'] ?? 'No location',
                'eventDate': eventData['eventDate'],
                'isTeamEvent': eventData['isTeamEvent'] ?? false,
              });
            }
          }
        }
      }

      setState(() {
        _teamInvitations = teamInvites;
        _pendingEvents = pendingEvents;
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching notifications: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  Future<void> _respondToTeamInvitation(
    String eventId,
    String teamId,
    bool accept,
  ) async {
    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // Update user's invitation status
      batch.update(
        FirebaseFirestore.instance.collection('users').doc(user!.uid),
        {'eventInvitations.$eventId.status': accept ? 'accepted' : 'rejected'},
      );

      if (accept) {
        // Add user to team members in the event document
        batch.update(
          FirebaseFirestore.instance.collection('events').doc(eventId),
          {
            'teams': FieldValue.arrayUnion([
              {
                'members': FieldValue.arrayUnion([user!.email]),
              },
            ]),
          },
        );
      }

      await batch.commit();

      // Check if team is now complete
      if (accept) {
        await _checkTeamCompletion(eventId, teamId);
      }

      // Update local state
      setState(() {
        _teamInvitations.removeWhere((invite) => invite['teamId'] == teamId);
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
      print('Error responding to team invitation: $e');
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
          await FirebaseFirestore.instance
              .collection('events')
              .doc(eventId)
              .get();

      List<dynamic> teams = eventDoc['teams'] ?? [];
      var team = teams.firstWhere(
        (t) => t['teamId'] == teamId,
        orElse: () => null,
      );

      if (team != null) {
        bool allAccepted = true;
        for (String memberEmail in team['members']) {
          QuerySnapshot userQuery =
              await FirebaseFirestore.instance
                  .collection('users')
                  .where('email', isEqualTo: memberEmail)
                  .limit(1)
                  .get();

          if (userQuery.docs.isNotEmpty) {
            var userDoc = userQuery.docs.first;
            if (userDoc['eventInvitations']?[eventId]?['status'] !=
                'accepted') {
              allAccepted = false;
              break;
            }
          }
        }

        if (allAccepted) {
          WriteBatch batch = FirebaseFirestore.instance.batch();

          // Update team status in the event document
          var updatedTeams =
              teams
                  .map(
                    (t) =>
                        t['teamId'] == teamId
                            ? {...t, 'status': 'accepted'}
                            : t,
                  )
                  .toList();

          batch.update(
            FirebaseFirestore.instance.collection('events').doc(eventId),
            {
              'teams': updatedTeams,
              'participants': FieldValue.increment(team['members'].length),
            },
          );

          // Update OD counts for all members
          for (String memberEmail in team['members']) {
            QuerySnapshot userQuery =
                await FirebaseFirestore.instance
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
        }
      }
    } catch (e) {
      print('Error checking team completion: $e');
    }
  }

  Future<void> _respondToEvent(
    String clubId,
    String eventId,
    String response,
  ) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 1),
          content: Text('Updating response...'),
        ),
      );

      await FirebaseFirestore.instance
          .collection('clubs')
          .doc(clubId)
          .collection('events')
          .doc(eventId)
          .update({'responses.${user!.email}': response});

      if (response == 'going') {
        DocumentSnapshot eventDoc =
            await FirebaseFirestore.instance
                .collection('clubs')
                .doc(clubId)
                .collection('events')
                .doc(eventId)
                .get();

        if (eventDoc.exists) {
          Map<String, dynamic> eventData =
              eventDoc.data() as Map<String, dynamic>;

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user!.uid)
              .collection('events')
              .doc(eventId)
              .set({
                'clubId': clubId,
                'eventId': eventId,
                'title': eventData['title'],
                'description': eventData['description'],
                'location': eventData['location'],
                'eventDate': eventData['eventDate'],
                'status': 'going',
                'respondedAt': Timestamp.now(),
              });
        }
      }

      setState(() {
        _pendingEvents.removeWhere((event) => event['id'] == eventId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response == 'going'
                ? 'You are going to the event!'
                : 'You declined the event',
          ),
          backgroundColor: response == 'going' ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      print('Error responding to event: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update response: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDate(Timestamp timestamp) {
    return DateFormat('EEE, MMM d, y - h:mm a').format(timestamp.toDate());
  }

  String _formatTimeSince(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    }
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Notifications",
          style: GoogleFonts.roboto(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.orangeAccent,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _hasError
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 60,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Error loading notifications',
                      style: TextStyle(fontSize: 18, color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _fetchNotifications,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
              : RefreshIndicator(
                onRefresh: _fetchNotifications,
                child: CustomScrollView(
                  slivers: [
                    if (_teamInvitations.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            "Team Invitations",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                            ),
                          ),
                        ),
                      ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final invite = _teamInvitations[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: const Icon(
                              Icons.group,
                              color: Colors.blue,
                              size: 36,
                            ),
                            title: Text(
                              invite['teamName'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Event: ${invite['eventTitle']}",
                                  style: const TextStyle(fontSize: 14),
                                ),
                                Text(
                                  "Invited ${_formatTimeSince(invite['invitedAt'])}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
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
                                      () => _respondToTeamInvitation(
                                        invite['eventId'],
                                        invite['teamId'],
                                        true,
                                      ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.red,
                                  ),
                                  onPressed:
                                      () => _respondToTeamInvitation(
                                        invite['eventId'],
                                        invite['teamId'],
                                        false,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }, childCount: _teamInvitations.length),
                    ),
                    if (_pendingEvents.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            "Event Invitations",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange[800],
                            ),
                          ),
                        ),
                      ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final event = _pendingEvents[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            leading: CircleAvatar(
                              backgroundColor: Colors.orangeAccent,
                              child: Text(
                                event['clubName'][0],
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(
                              event['title'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  event['clubName'],
                                  style: const TextStyle(fontSize: 14),
                                ),
                                Text(
                                  _formatDate(event['eventDate']),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton(
                                  onPressed:
                                      () => _respondToEvent(
                                        event['clubId'],
                                        event['id'],
                                        'going',
                                      ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Accept'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed:
                                      () => _respondToEvent(
                                        event['clubId'],
                                        event['id'],
                                        'declined',
                                      ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text('Decline'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }, childCount: _pendingEvents.length),
                    ),
                    if (_teamInvitations.isEmpty && _pendingEvents.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.notifications_off,
                                size: 60,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No new notifications',
                                style: GoogleFonts.roboto(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'You\'re all caught up!',
                                style: GoogleFonts.roboto(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fetchNotifications,
        backgroundColor: Colors.orangeAccent,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
