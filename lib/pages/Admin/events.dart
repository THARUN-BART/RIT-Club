import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  DateTime? registrationDate;
  DateTime? eventDate;

  Future<String?> fetchLoginClubName() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot snapshot =
          await FirebaseFirestore.instance.collection('clubs').doc().get();
      return snapshot['name'] as String?;
    }
    return null;
  }

  Future<void> pickDate(
    BuildContext context,
    Function(DateTime) onDatePicked,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.orangeAccent,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      onDatePicked(picked);
    }
  }

  void showEventDialog(BuildContext context) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final participantLimitController = TextEditingController();
    final locationController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return FutureBuilder<String?>(
              future: fetchLoginClubName(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Colors.orangeAccent,
                    ),
                  );
                }

                final clubName = snapshot.data ?? 'Unknown Club';

                return AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  title: Text(
                    "Create Event",
                    style: GoogleFonts.aclonica(fontSize: 22),
                    textAlign: TextAlign.center,
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(
                            Icons.group,
                            color: Colors.orangeAccent,
                          ),
                          title: const Text('Club'),
                          subtitle: Text(
                            clubName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: titleController,
                          decoration: _inputDecoration(
                            "Event Title",
                            Icons.title,
                          ),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: descriptionController,
                          maxLines: 3,
                          maxLength: 1000,
                          decoration: _inputDecoration(
                            "Event Description",
                            Icons.description,
                          ),
                        ),
                        const SizedBox(height: 15),
                        TextField(
                          controller: locationController,
                          decoration: _inputDecoration(
                            "Event Location",
                            Icons.location_on,
                          ),
                        ),
                        const SizedBox(height: 15),
                        _buildDatePickerRow(
                          "Last Date for Registration",
                          registrationDate,
                          (date) => setState(() => registrationDate = date),
                          Icons.calendar_today,
                        ),
                        const SizedBox(height: 15),
                        _buildDatePickerRow("Event Date", eventDate, (date) {
                          if (registrationDate != null &&
                              date.isBefore(registrationDate!)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Event Date cannot be earlier than Registration Date",
                                ),
                              ),
                            );
                          } else {
                            setState(() => eventDate = date);
                          }
                        }, Icons.event),
                        const SizedBox(height: 15),
                        TextField(
                          controller: participantLimitController,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration(
                            "Participant Limit",
                            Icons.people,
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (titleController.text.isEmpty ||
                            descriptionController.text.isEmpty ||
                            locationController.text.isEmpty ||
                            registrationDate == null ||
                            eventDate == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Please fill all required fields"),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        try {
                          await FirebaseFirestore.instance
                              .collection('events')
                              .add({
                                'title': titleController.text,
                                'description': descriptionController.text,
                                'clubName': clubName,
                                'location': locationController.text,
                                'registrationDate':
                                    registrationDate?.toIso8601String(),
                                'eventDate': eventDate?.toIso8601String(),
                                'participantLimit':
                                    int.tryParse(
                                      participantLimitController.text,
                                    ) ??
                                    0,
                                'participants': 0,
                                'timestamp': DateTime.now(),
                              });

                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Event created successfully!"),
                              backgroundColor: Colors.green,
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Error creating event: $e"),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text("Save"),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  static InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.orangeAccent),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Colors.orangeAccent, width: 2),
      ),
      prefixIcon: Icon(icon, color: Colors.orangeAccent),
    );
  }

  Widget _buildDatePickerRow(
    String label,
    DateTime? selectedDate,
    Function(DateTime) onDatePicked,
    IconData icon,
  ) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    return InkWell(
      onTap: () => pickDate(context, onDatePicked),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.orangeAccent),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  selectedDate != null
                      ? dateFormat.format(selectedDate)
                      : "Select date",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                        selectedDate != null
                            ? FontWeight.w500
                            : FontWeight.normal,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.arrow_drop_down, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("EVENTS", style: GoogleFonts.aclonica(fontSize: 25)),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showEventDialog(context),
        backgroundColor: Colors.orangeAccent,
        tooltip: "Create Event",
        elevation: 4,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance
                .collection('events')
                .orderBy('eventDate')
                .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            );
          }

          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          final events = snapshot.data?.docs ?? [];

          if (events.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "No events found",
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Press the + button to create a new event",
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index].data() as Map<String, dynamic>;
              final eventDate =
                  event['eventDate'] != null
                      ? DateTime.parse(event['eventDate'])
                      : null;
              final isUpcoming =
                  eventDate != null && eventDate.isAfter(DateTime.now());

              return Card(
                color: isUpcoming ? Colors.white : Colors.grey.shade200,
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  title: Text(event['title'] ?? "Untitled Event"),
                  subtitle: Text(event['description'] ?? ""),
                  trailing: Text(
                    eventDate != null
                        ? DateFormat('MMM dd, yyyy').format(eventDate)
                        : "",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class EventCard extends StatelessWidget {
  final String eventId;
  final String title;
  final String description;
  final String clubName;
  final String location;
  final DateTime? eventDate;
  final int participantLimit;
  final int currentParticipants;
  final bool isUpcoming;
  final bool isAdmin;

  const EventCard({
    required this.eventId,
    required this.title,
    required this.description,
    required this.clubName,
    required this.location,
    this.eventDate,
    required this.participantLimit,
    required this.currentParticipants,
    required this.isUpcoming,
    this.isAdmin = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE, MMM d, y');
    final timeFormat = DateFormat('h:mm a');

    final formattedDate =
        eventDate != null ? dateFormat.format(eventDate!) : 'Date TBD';

    final formattedTime =
        eventDate != null ? timeFormat.format(eventDate!) : 'Time TBD';

    final isSpaceLimited = participantLimit > 0;
    final spacesLeft = participantLimit - currentParticipants;
    final isFull = isSpaceLimited && spacesLeft <= 0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color:
              isUpcoming
                  ? Colors.orangeAccent.withOpacity(0.3)
                  : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          _showEventDetails(context);
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with club name and date
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color:
                    isUpcoming
                        ? Colors.orangeAccent.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      clubName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color:
                            isUpcoming
                                ? Colors.orangeAccent
                                : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Text(
                    isUpcoming ? 'Upcoming' : 'Past Event',
                    style: TextStyle(
                      color: isUpcoming ? Colors.green : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Event title and description
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    description.length > 120
                        ? '${description.substring(0, 120)}...'
                        : description,
                    style: TextStyle(color: Colors.grey.shade700, height: 1.3),
                  ),
                ],
              ),
            ),

            // Event details
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: Colors.redAccent, size: 18),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      location,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 8),

            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    color: Colors.blueAccent,
                    size: 18,
                  ),
                  SizedBox(width: 4),
                  Text(
                    formattedDate,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  SizedBox(width: 16),
                  Icon(Icons.access_time, color: Colors.greenAccent, size: 18),
                  SizedBox(width: 4),
                  Text(
                    formattedTime,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),

            // Participants info (removed register button for admin)
            Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isSpaceLimited
                              ? 'Participants: $currentParticipants/$participantLimit'
                              : 'Participants: $currentParticipants',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (isSpaceLimited && isUpcoming)
                          Text(
                            isFull
                                ? 'No spaces left'
                                : '$spacesLeft spaces left',
                            style: TextStyle(
                              color: isFull ? Colors.red : Colors.green,
                              fontSize: 12,
                            ),
                          ),
                      ],
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

  void _showEventDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final dateFormat = DateFormat('EEEE, MMMM d, y');
        final timeFormat = DateFormat('h:mm a');

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      margin: EdgeInsets.only(top: 8, bottom: 12),
                      height: 4,
                      width: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),

                  // Event title and organization
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Organized by $clubName',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),

                  Divider(height: 32),

                  // Event details (time, location, etc.)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date and time
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.calendar_today,
                                color: Colors.blue,
                              ),
                            ),
                            SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  eventDate != null
                                      ? dateFormat.format(eventDate!)
                                      : 'Date TBD',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  eventDate != null
                                      ? timeFormat.format(eventDate!)
                                      : 'Time TBD',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ],
                        ),

                        SizedBox(height: 16),

                        // Location
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.location_on, color: Colors.red),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Location',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 16,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    location,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 16),

                        // Participants
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.people, color: Colors.green),
                            ),
                            SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Participants',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  participantLimit > 0
                                      ? '$currentParticipants/$participantLimit registered'
                                      : '$currentParticipants registered',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  Divider(height: 32),

                  // Event description
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'About the Event',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          description,
                          style: TextStyle(
                            height: 1.5,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
