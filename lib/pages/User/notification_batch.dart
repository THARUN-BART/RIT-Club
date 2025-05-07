import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationBadge extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;

  const NotificationBadge({
    Key? key,
    required this.child,
    required this.onPressed,
  }) : super(key: key);

  @override
  State<NotificationBadge> createState() => _NotificationBadgeState();
}

class _NotificationBadgeState extends State<NotificationBadge> {
  final User? user = FirebaseAuth.instance.currentUser;
  int _notificationCount = 0;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _setupNotificationListener();
  }

  void _setupNotificationListener() {
    if (user == null) {
      setState(() => _notificationCount = 0);
      return;
    }

    _subscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .snapshots()
        .listen((userDoc) {
          if (!userDoc.exists) {
            setState(() => _notificationCount = 0);
            return;
          }

          // Count pending event invitations
          var invitations = userDoc.data()?['eventInvitations'] ?? {};
          int invitationCount = 0;
          invitations.forEach((key, value) {
            if (value['status'] == 'pending') {
              invitationCount++;
            }
          });

          // Count pending individual events
          List<String> followedClubs = List<String>.from(
            userDoc['followedClubs'] ?? [],
          );
          int eventCount = 0;

          if (followedClubs.isNotEmpty) {
            // This would be more efficient with a Cloud Function
            for (String clubId in followedClubs) {
              FirebaseFirestore.instance
                  .collection('clubs')
                  .doc(clubId)
                  .collection('events')
                  .where('status', isEqualTo: 'active')
                  .where('eventDate', isGreaterThan: Timestamp.now())
                  .get()
                  .then((snapshot) {
                    for (var doc in snapshot.docs) {
                      var responses = doc['responses'] ?? {};
                      if (!responses.containsKey(user!.email)) {
                        eventCount++;
                      }
                    }
                  });
            }
          }

          if (mounted) {
            setState(() => _notificationCount = invitationCount + eventCount);
          }
        });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: widget.child,
          onPressed: () {
            widget.onPressed();
            setState(() => _notificationCount = 0);
          },
        ),
        if (_notificationCount > 0)
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                _notificationCount > 99 ? '99+' : _notificationCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
