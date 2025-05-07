import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class FeedbackPage extends StatefulWidget {
  final String clubId;
  final String clubName;

  const FeedbackPage({required this.clubId, required this.clubName, Key? key})
    : super(key: key);

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  int _currentTabIndex = 0;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Club Feedback",
          style: GoogleFonts.aclonica(fontSize: 25, color: Colors.white),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _buildEventTypeTabs(),
        ),
      ),
      body: _buildEventList(),
    );
  }

  Widget _buildEventTypeTabs() {
    return Container(
      height: 48,
      decoration: BoxDecoration(color: Colors.grey[900]),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _currentTabIndex = 0),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color:
                          _currentTabIndex == 0
                              ? Colors.orange
                              : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  'Active Events',
                  style: GoogleFonts.poppins(
                    color: _currentTabIndex == 0 ? Colors.orange : Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _currentTabIndex = 1),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color:
                          _currentTabIndex == 1
                              ? Colors.orange
                              : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  'Past Events',
                  style: GoogleFonts.poppins(
                    color: _currentTabIndex == 1 ? Colors.orange : Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventList() {
    final status = _currentTabIndex == 0 ? 'active' : 'past';

    return StreamBuilder<QuerySnapshot>(
      stream:
          _firestore
              .collection('events')
              .where('clubId', isEqualTo: widget.clubId)
              .where('status', isEqualTo: status)
              .orderBy('eventDateTime', descending: true)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading events: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'No ${status} events found',
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final event = snapshot.data!.docs[index];
            final eventData = event.data() as Map<String, dynamic>;
            final eventId = event.id;

            return EventFeedbackCard(
              eventId: eventId,
              eventName: eventData['title']?.toString() ?? 'Untitled Event',
              eventDateTime: _parseDateTime(eventData['eventDateTime']),
              eventLocation:
                  eventData['location']?.toString() ?? 'Location not specified',
              status: status,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => EventFeedbackDetails(
                          eventId: eventId,
                          eventName:
                              eventData['title']?.toString() ??
                              'Untitled Event',
                          clubName: widget.clubName,
                          clubId: widget.clubId,
                        ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  DateTime? _parseDateTime(dynamic date) {
    try {
      if (date == null) return null;
      if (date is Timestamp) return date.toDate();
      if (date is String) return DateTime.tryParse(date);
      return null;
    } catch (e) {
      debugPrint('Error parsing date: $e');
      return null;
    }
  }
}

class EventFeedbackCard extends StatelessWidget {
  final String eventId;
  final String eventName;
  final DateTime? eventDateTime;
  final String eventLocation;
  final String status;
  final VoidCallback onTap;

  const EventFeedbackCard({
    required this.eventId,
    required this.eventName,
    required this.eventDateTime,
    required this.eventLocation,
    required this.status,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          status == 'active'
                              ? Colors.green.withOpacity(0.2)
                              : Colors.grey.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        color: status == 'active' ? Colors.green : Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.feedback, color: Colors.orange, size: 20),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                eventName,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (eventDateTime != null) ...[
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat(
                        'MMM dd, yyyy • hh:mm a',
                      ).format(eventDateTime!),
                      style: GoogleFonts.poppins(color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    eventLocation,
                    style: GoogleFonts.poppins(color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FutureBuilder<QuerySnapshot>(
                future:
                    FirebaseFirestore.instance
                        .collection('events')
                        .doc(eventId)
                        .collection('feedback')
                        .get(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text(
                      'Loading feedback...',
                      style: TextStyle(color: Colors.grey),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Text(
                      'Error loading feedback',
                      style: TextStyle(color: Colors.red),
                    );
                  }

                  final feedbackCount = snapshot.data?.docs.length ?? 0;
                  return Text(
                    '$feedbackCount ${feedbackCount == 1 ? 'feedback' : 'feedbacks'}',
                    style: GoogleFonts.poppins(
                      color: Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EventFeedbackDetails extends StatelessWidget {
  final String eventId;
  final String eventName;
  final String clubName;
  final String clubId;

  const EventFeedbackDetails({
    required this.eventId,
    required this.eventName,
    required this.clubName,
    required this.clubId,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Feedback Details",
          style: GoogleFonts.aclonica(fontSize: 20, color: Colors.orange),
        ),
        iconTheme: const IconThemeData(color: Colors.orange),
      ),
      body: Column(
        children: [
          // Event header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eventName,
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(clubName, style: GoogleFonts.poppins(color: Colors.grey)),
              ],
            ),
          ),

          // Feedback list
          Expanded(child: EventFeedbackList(eventId: eventId)),
        ],
      ),
    );
  }
}

class EventFeedbackList extends StatelessWidget {
  final String eventId;

  const EventFeedbackList({required this.eventId, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('events')
              .doc(eventId)
              .collection('feedback')
              .orderBy('submittedAt', descending: true)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.feedback_outlined,
                  size: 60,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No feedback available for this event',
                  style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final feedbackDoc = snapshot.data!.docs[index];
            final feedback = feedbackDoc.data() as Map<String, dynamic>;
            return FeedbackItemCard(feedback: feedback);
          },
        );
      },
    );
  }
}

class FeedbackItemCard extends StatelessWidget {
  final Map<String, dynamic> feedback;

  const FeedbackItemCard({required this.feedback, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final username = feedback['userName']?.toString() ?? 'Anonymous';
    final comment = feedback['comment']?.toString() ?? '[No comment provided]';
    final rating = feedback['rating'] ?? 0;
    final submittedAt = feedback['submittedAt'];
    final eventName = feedback['eventName']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.orange.withOpacity(0.2),
                  child: Text(
                    username.isNotEmpty
                        ? username.substring(0, 1).toUpperCase()
                        : 'A',
                    style: const TextStyle(
                      color: Colors.orange,
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
                        username,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (eventName.isNotEmpty)
                        Text(
                          eventName,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                // Rating display
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getRatingColor(rating).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.star,
                        size: 16,
                        color: _getRatingColor(rating),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        rating.toString(),
                        style: TextStyle(
                          color: _getRatingColor(rating),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(comment, style: GoogleFonts.poppins(fontSize: 15)),
            const SizedBox(height: 8),
            if (submittedAt != null)
              Text(
                _formatTimestamp(submittedAt),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _getRatingColor(dynamic rating) {
    final ratingValue = rating is int ? rating : 0;

    if (ratingValue >= 4) return Colors.green;
    if (ratingValue >= 3) return Colors.orange;
    if (ratingValue >= 2) return Colors.amber;
    return Colors.red;
  }

  String _formatTimestamp(dynamic timestamp) {
    try {
      if (timestamp is Timestamp) {
        return DateFormat('MMM dd, yyyy • hh:mm a').format(timestamp.toDate());
      }
      if (timestamp is String) {
        // Try to parse the string timestamp
        final dateTime = DateTime.tryParse(timestamp);
        if (dateTime != null) {
          return DateFormat('MMM dd, yyyy • hh:mm a').format(dateTime);
        }
        return timestamp;
      }
      return '';
    } catch (e) {
      return '';
    }
  }
}
