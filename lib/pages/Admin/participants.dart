import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class Participants extends StatefulWidget {
  final String clubName;

  const Participants({super.key, required this.clubName});

  @override
  State<Participants> createState() => _ParticipantsState();
}

class _ParticipantsState extends State<Participants> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Participants",
          style: GoogleFonts.aclonica(fontSize: 25, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: Container(
        child: StreamBuilder<QuerySnapshot>(
          stream:
              FirebaseFirestore.instance
                  .collection('events')
                  .where('clubName', isEqualTo: widget.clubName)
                  .where(
                    'status',
                    isEqualTo: 'active',
                  ) // Filter for specifically active events
                  .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.orangeAccent,
                  ),
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Text(
                  "No Active Events Found!",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.grey[700],
                  ),
                ),
              );
            }

            final events = snapshot.data!.docs;

            return ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                return FutureBuilder<QuerySnapshot>(
                  future:
                      FirebaseFirestore.instance
                          .collection('events')
                          .doc(event.id)
                          .collection('participants')
                          .get(),
                  builder: (context, participantsSnapshot) {
                    int participantCount = 0;
                    if (participantsSnapshot.hasData) {
                      participantCount = participantsSnapshot.data!.docs.length;
                    }

                    return EventCard(
                      eventId: event.id,
                      eventName: event['title'],
                      eventDate: event['eventDateTime'],
                      eventLocation: event['location'],
                      clubName: widget.clubName,
                      participantCount: participantCount,
                      participantLimit: event['participantLimit'] ?? 0,
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class EventCard extends StatelessWidget {
  final String eventId;
  final String eventName;
  final String eventDate;
  final String eventLocation;
  final String clubName;
  final int participantCount;
  final int participantLimit;

  const EventCard({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.eventDate,
    required this.eventLocation,
    required this.clubName,
    required this.participantCount,
    required this.participantLimit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 4,
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => ParticipantDetailsPage(
                    eventId: eventId,
                    eventName: eventName,
                    clubName: clubName,
                  ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eventName,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.orangeAccent,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Date: ${_formatDateTime(eventDate)}",
                style: GoogleFonts.poppins(fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                "Location: $eventLocation",
                style: GoogleFonts.poppins(fontSize: 16),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value:
                    participantLimit > 0
                        ? participantCount / participantLimit
                        : 0,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  participantCount >= participantLimit
                      ? Colors.red
                      : Colors.green,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Participants: $participantCount/$participantLimit",
                style: GoogleFonts.poppins(fontSize: 14),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.people, color: Colors.orangeAccent, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    "View Participants",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.orangeAccent,
                    size: 14,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(String dateTime) {
    try {
      final dt = DateTime.parse(dateTime);
      return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return dateTime;
    }
  }
}

class ParticipantDetailsPage extends StatefulWidget {
  final String eventId;
  final String eventName;
  final String clubName;

  const ParticipantDetailsPage({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.clubName,
  });

  @override
  State<ParticipantDetailsPage> createState() => _ParticipantDetailsPageState();
}

class _ParticipantDetailsPageState extends State<ParticipantDetailsPage> {
  String searchQuery = '';
  bool isLoading = false;

  // Available attendance options
  final List<String> attendanceOptions = ['Present', 'Absent'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Event Participants",
          style: GoogleFonts.aclonica(fontSize: 20, color: Colors.orangeAccent),
        ),
        iconTheme: const IconThemeData(color: Colors.orangeAccent),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.orangeAccent.withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.eventName,
                  style: GoogleFonts.poppins(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.orangeAccent,
                  ),
                ),
                Text(
                  widget.clubName,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          // Search Bar for Registration Number
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by Registration Number',
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.orangeAccent,
                ),
                filled: true,
                fillColor: Colors.transparent,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: Colors.orangeAccent),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.trim();
                });
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Participants",
                  style: GoogleFonts.poppins(
                    fontSize: 25,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                if (searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        searchQuery = '';
                      });
                    },
                    child: Text(
                      "Clear Filter",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.orangeAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collection('events')
                          .doc(widget.eventId)
                          .collection('participants')
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.orangeAccent,
                          ),
                        ),
                      );
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 60,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "No participants yet",
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final participants = snapshot.data!.docs;

                    // Filter participants by registration number
                    final filteredParticipants =
                        searchQuery.isEmpty
                            ? participants
                            : participants.where((participant) {
                              final participantData =
                                  participant.data() as Map<String, dynamic>;
                              final regNo =
                                  participantData['regNo'] as String? ?? '';
                              return regNo.toLowerCase().contains(
                                searchQuery.toLowerCase(),
                              );
                            }).toList();

                    if (filteredParticipants.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 60,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "No matching registration numbers",
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: filteredParticipants.length,
                      itemBuilder: (context, index) {
                        final participantData =
                            filteredParticipants[index].data()
                                as Map<String, dynamic>;
                        final participantId = filteredParticipants[index].id;
                        final attendance =
                            participantData['Attendance'] as String? ??
                            'Not Marked';

                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orangeAccent.withOpacity(
                                0.2,
                              ),
                              child: Text(
                                (participantData['name'] as String?)
                                        ?.substring(0, 1)
                                        .toUpperCase() ??
                                    'U',
                                style: const TextStyle(
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  participantData['name'] ?? "Unknown User",
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  "ID: $participantId",
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(participantData['email'] ?? "No email"),
                                if (participantData['regNo'] != null)
                                  RichText(
                                    text: TextSpan(
                                      children: _highlightRegNo(
                                        "Reg No: ${participantData['regNo']}",
                                        searchQuery,
                                      ),
                                    ),
                                  ),
                                if (participantData['department'] != null)
                                  Text(
                                    "Department: ${participantData['department']}",
                                  ),
                                Row(
                                  children: [
                                    Text(
                                      "Attendance: ",
                                      style: GoogleFonts.poppins(),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        _showAttendanceDialog(
                                          context,
                                          participantId,
                                          attendance,
                                        );
                                      },
                                      child: Text(
                                        attendance,
                                        style: GoogleFonts.poppins(
                                          color: _getAttendanceColor(
                                            attendance,
                                          ),
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    GestureDetector(
                                      onTap: () {
                                        _showAttendanceDialog(
                                          context,
                                          participantId,
                                          attendance,
                                        );
                                      },
                                      child: const Icon(
                                        Icons.edit,
                                        size: 16,
                                        color: Colors.orangeAccent,
                                      ),
                                    ),
                                  ],
                                ),
                                if (participantData['phoneNumber'] != null)
                                  Text(
                                    "Phone: ${participantData['phoneNumber']}",
                                  ),

                                if (participantData['registeredAt'] != null)
                                  Text(
                                    "Registered: ${_formatTimestamp(participantData['registeredAt'])}",
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                            isThreeLine: true,
                          ),
                        );
                      },
                    );
                  },
                ),
                // Loading indicator overlay
                if (isLoading)
                  Container(
                    color: Colors.black.withOpacity(0.3),
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.orangeAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getAttendanceColor(String attendance) {
    switch (attendance.toLowerCase()) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Show dialog to update attendance
  void _showAttendanceDialog(
    BuildContext context,
    String participantId,
    String currentAttendance,
  ) {
    String selectedAttendance = currentAttendance;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Update Attendance',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.orangeAccent,
            ),
          ),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Container(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children:
                      attendanceOptions.map((option) {
                        return RadioListTile<String>(
                          title: Text(option, style: GoogleFonts.poppins()),
                          value: option,
                          groupValue: selectedAttendance,
                          activeColor: Colors.orangeAccent,
                          onChanged: (value) {
                            setState(() {
                              selectedAttendance = value!;
                            });
                          },
                        );
                      }).toList(),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent,
              ),
              onPressed: () {
                _updateAttendance(participantId, selectedAttendance);
                Navigator.pop(context);
              },
              child: Text(
                'Update',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  // Update attendance in Firestore
  Future<void> _updateAttendance(
    String participantId,
    String attendance,
  ) async {
    try {
      setState(() {
        isLoading = true;
      });

      await FirebaseFirestore.instance
          .collection('events')
          .doc(widget.eventId)
          .collection('participants')
          .doc(participantId)
          .update({
            'Attendance': attendance,
            'attendanceUpdatedAt': FieldValue.serverTimestamp(),
          });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Attendance updated successfully',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to update attendance: $e',
            style: GoogleFonts.poppins(),
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  List<TextSpan> _highlightRegNo(String text, String query) {
    if (query.isEmpty) {
      return [
        TextSpan(
          text: text,
          style: GoogleFonts.poppins(color: Colors.orangeAccent),
        ),
      ];
    }

    final regNoText = text.toLowerCase();
    final queryText = query.toLowerCase();

    if (!regNoText.contains(queryText)) {
      return [TextSpan(text: text, style: GoogleFonts.poppins())];
    }

    List<TextSpan> spans = [];
    int start = 0;

    // Find all occurrences of query in the text
    int index = regNoText.indexOf(queryText);
    while (index != -1) {
      // Add the text before the match
      if (index > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, index),
            style: GoogleFonts.poppins(color: Colors.black87),
          ),
        );
      }

      // Add the highlighted match
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: GoogleFonts.poppins(
            color: Colors.orangeAccent,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.orangeAccent.withOpacity(0.2),
          ),
        ),
      );

      start = index + query.length;
      index = regNoText.indexOf(queryText, start);
    }

    // Add the remaining text after the last match
    if (start < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(start),
          style: GoogleFonts.poppins(color: Colors.black87),
        ),
      );
    }

    return spans;
  }

  String _formatTimestamp(Timestamp timestamp) {
    final dt = timestamp.toDate();
    return "${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
