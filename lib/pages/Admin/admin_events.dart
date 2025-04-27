import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'admin_home.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime? registrationDate;
  TimeOfDay? registrationTime;
  DateTime? eventDate;
  TimeOfDay? eventTime;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<String?> fetchLoginClubName() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot snapshot =
          await FirebaseFirestore.instance
              .collection('clubs')
              .doc(user.uid)
              .get();
      return snapshot['name'] as String?;
    }
    return null;
  }

  Future<void> pickDate(
    BuildContext context,
    Function(DateTime) onDatePicked, {
    DateTime? minDate,
  }) async {
    final DateTime minimumDate = minDate ?? DateTime.now();

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: minimumDate,
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

  Future<void> pickTime(
    BuildContext context,
    Function(TimeOfDay) onTimePicked,
  ) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
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
      onTimePicked(picked);
    }
  }

  void showEventDialog(BuildContext context) {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final participantLimitController = TextEditingController();
    final locationController = TextEditingController();

    registrationDate = null;
    registrationTime = null;
    eventDate = null;
    eventTime = null;

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

                final clubName = snapshot.data ?? AdminHome.currentClubName;

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
                            clubName ?? "Your Club",
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
                        _buildTimePickerRow(
                          "Registration Time",
                          registrationTime,
                          (time) => setState(() => registrationTime = time),
                          Icons.access_time,
                        ),
                        const SizedBox(height: 15),
                        _buildDatePickerRow(
                          "Event Date",
                          eventDate,
                          (date) {
                            setState(() => eventDate = date);
                          },
                          Icons.event,
                          minDate: registrationDate,
                        ),
                        const SizedBox(height: 15),
                        _buildTimePickerRow(
                          "Event Time",
                          eventTime,
                          (time) => setState(() => eventTime = time),
                          Icons.access_time,
                        ),
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
                            registrationTime == null ||
                            eventDate == null ||
                            eventTime == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Please fill all required fields"),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        final registrationDateTime = DateTime(
                          registrationDate!.year,
                          registrationDate!.month,
                          registrationDate!.day,
                          registrationTime!.hour,
                          registrationTime!.minute,
                        );

                        final eventDateTime = DateTime(
                          eventDate!.year,
                          eventDate!.month,
                          eventDate!.day,
                          eventTime!.hour,
                          eventTime!.minute,
                        );

                        if (eventDateTime.isBefore(registrationDateTime)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "Event date must be after registration date",
                              ),
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
                                'clubId':
                                    FirebaseAuth.instance.currentUser?.uid,
                                'location': locationController.text,
                                'registrationDateTime':
                                    registrationDateTime.toIso8601String(),
                                'eventDateTime':
                                    eventDateTime.toIso8601String(),
                                'participantLimit':
                                    int.tryParse(
                                      participantLimitController.text,
                                    ) ??
                                    0,
                                'participants': 0,
                                'createdAt': DateTime.now().toIso8601String(),
                                'status': 'active',
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
    IconData icon, {
    DateTime? minDate,
  }) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    return InkWell(
      onTap: () => pickDate(context, onDatePicked, minDate: minDate),
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

  Widget _buildTimePickerRow(
    String label,
    TimeOfDay? selectedTime,
    Function(TimeOfDay) onTimePicked,
    IconData icon,
  ) {
    return InkWell(
      onTap: () => pickTime(context, onTimePicked),
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
                  selectedTime != null
                      ? selectedTime.format(context)
                      : "Select time",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                        selectedTime != null
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.orangeAccent,
          labelColor: Colors.orangeAccent,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Cancelled'),
            Tab(text: 'Past'),
          ],
        ),
      ),
      floatingActionButton:
          _tabController.index == 0
              ? FloatingActionButton(
                onPressed: () => showEventDialog(context),
                backgroundColor: Colors.orangeAccent,
                tooltip: "Create Event",
                elevation: 4,
                child: const Icon(Icons.add, color: Colors.white),
              )
              : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEventsList('active'),
          _buildEventsList('cancelled'),
          _buildEventsList('past'),
        ],
      ),
    );
  }

  Widget _buildEventsList(String status) {
    Query eventsQuery;
    DateTime now = DateTime.now();
    String? currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId != null) {
      if (status == 'cancelled') {
        eventsQuery = FirebaseFirestore.instance
            .collection('events')
            .where('clubId', isEqualTo: currentUserId)
            .where('status', isEqualTo: 'cancelled')
            .orderBy('eventDateTime', descending: true);
      } else if (status == 'past') {
        eventsQuery = FirebaseFirestore.instance
            .collection('events')
            .where('clubId', isEqualTo: currentUserId)
            .where('status', isEqualTo: 'active')
            .orderBy('eventDateTime', descending: true);
      } else {
        eventsQuery = FirebaseFirestore.instance
            .collection('events')
            .where('clubId', isEqualTo: currentUserId)
            .where('status', isEqualTo: 'active')
            .orderBy('eventDateTime');
      }
    } else {
      eventsQuery = FirebaseFirestore.instance.collection('events').limit(0);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: eventsQuery.snapshots(),
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
        List<QueryDocumentSnapshot> filteredEvents = [];

        if (status == 'active') {
          filteredEvents =
              events.where((doc) {
                final event = doc.data() as Map<String, dynamic>;
                if (event['eventDateTime'] == null) return false;
                try {
                  final eventDate = DateTime.parse(event['eventDateTime']);
                  // Create a date that represents the end of the event day (next day at midnight)
                  final endOfEventDay = DateTime(
                    eventDate.year,
                    eventDate.month,
                    eventDate.day + 1,
                  );
                  // Event is active if today is before or equal to the event's end day
                  return now.isBefore(endOfEventDay);
                } catch (e) {
                  return false;
                }
              }).toList();
        } else if (status == 'past') {
          filteredEvents =
              events.where((doc) {
                final event = doc.data() as Map<String, dynamic>;
                if (event['eventDateTime'] == null) return false;
                try {
                  final eventDate = DateTime.parse(event['eventDateTime']);
                  // Create a date that represents the end of the event day (next day at midnight)
                  final endOfEventDay = DateTime(
                    eventDate.year,
                    eventDate.month,
                    eventDate.day + 1,
                  );
                  // Event is past if today is after the event's end day
                  return now.isAfter(endOfEventDay) ||
                      now.isAtSameMomentAs(endOfEventDay);
                } catch (e) {
                  return false;
                }
              }).toList();
        } else {
          filteredEvents = events;
        }

        if (filteredEvents.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  status == 'active'
                      ? Icons.event_available
                      : status == 'cancelled'
                      ? Icons.event_busy
                      : Icons.history,
                  size: 80,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  status == 'active'
                      ? "No active events"
                      : status == 'cancelled'
                      ? "No cancelled events"
                      : "No past events",
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                if (status == 'active')
                  const Text(
                    "Press the + button to create a new event",
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filteredEvents.length,
          itemBuilder: (context, index) {
            final event = filteredEvents[index].data() as Map<String, dynamic>;
            final eventDateTime =
                event['eventDateTime'] != null
                    ? DateTime.parse(event['eventDateTime'])
                    : null;

            final isCancelled = event['status'] == 'cancelled';

            // Check if the event is past (after midnight of the event day)
            final isPast =
                eventDateTime != null
                    ? DateTime.now().isAfter(
                      DateTime(
                        eventDateTime.year,
                        eventDateTime.month,
                        eventDateTime.day + 1,
                      ),
                    )
                    : false;

            return EventCard(
              eventId: filteredEvents[index].id,
              title: event['title'] ?? "Untitled Event",
              description: event['description'] ?? "",
              clubName: event['clubName'] ?? "Unknown Club",
              location: event['location'] ?? "TBD",
              eventDate: eventDateTime,
              participantLimit: event['participantLimit'] ?? 0,
              currentParticipants: event['participants'] ?? 0,
              isUpcoming: !isPast,
              isAdmin: true,
              isCancelled: isCancelled,
              isPastEvent: isPast,
            );
          },
        );
      },
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
  final bool isCancelled;
  final bool isPastEvent;

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
    this.isCancelled = false,
    required this.isPastEvent,
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
              isCancelled
                  ? Colors.red.withOpacity(0.3)
                  : isUpcoming
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color:
                    isCancelled
                        ? Colors.red.withOpacity(0.1)
                        : isUpcoming
                        ? Colors.orangeAccent.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
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
                            isCancelled
                                ? Colors.red
                                : isUpcoming
                                ? Colors.orangeAccent
                                : Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Text(
                    isCancelled
                        ? 'Cancelled'
                        : isUpcoming
                        ? 'Upcoming'
                        : 'Past Event',
                    style: TextStyle(
                      color:
                          isCancelled
                              ? Colors.red
                              : isUpcoming
                              ? Colors.green
                              : Colors.grey,
                      fontSize: 12,
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
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description.length > 120
                        ? '${description.substring(0, 120)}...'
                        : description,
                    style: TextStyle(color: Colors.grey.shade700, height: 1.3),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on,
                    color: Colors.redAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      location,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    color: Colors.blueAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formattedDate,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(width: 16),
                  const Icon(
                    Icons.access_time,
                    color: Colors.greenAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    formattedTime,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
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
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        if (isSpaceLimited && isUpcoming && !isCancelled)
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
                  // Only show edit button for upcoming, non-cancelled events that aren't past
                  if (isAdmin && isUpcoming && !isCancelled && !isPastEvent)
                    TextButton.icon(
                      onPressed: () {
                        _showEditEventDialog(context);
                      },
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blueAccent,
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
      shape: const RoundedRectangleBorder(
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
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 12),
                      height: 4,
                      width: 40,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Organized by $clubName',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        if (isCancelled)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'CANCELLED',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.calendar_today,
                                color: Colors.blue,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Date & Time',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    eventDate != null
                                        ? '${dateFormat.format(eventDate!)}\n${timeFormat.format(eventDate!)}'
                                        : 'Date and time to be determined',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Location',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    location,
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.people,
                                color: Colors.green,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Participants',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    participantLimit > 0
                                        ? '$currentParticipants/$participantLimit registered'
                                        : '$currentParticipants registered',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'About this event',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          description,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 32),
                        if (isAdmin &&
                            isUpcoming &&
                            !isCancelled &&
                            !isPastEvent)
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _showEditEventDialog(context);
                                  },
                                  icon: const Icon(Icons.edit),
                                  label: const Text('Edit Event'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueAccent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    _showCancelEventDialog(context);
                                  },
                                  icon: const Icon(Icons.cancel),
                                  label: const Text('Cancel Event'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 40),
                      ],
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

  void _showEditEventDialog(BuildContext context) {
    final titleController = TextEditingController(text: title);
    final descriptionController = TextEditingController(text: description);
    final locationController = TextEditingController(text: location);
    final participantLimitController = TextEditingController(
      text: participantLimit > 0 ? participantLimit.toString() : '',
    );

    DateTime? updatedEventDate = eventDate;
    TimeOfDay? updatedEventTime =
        eventDate != null
            ? TimeOfDay(hour: eventDate!.hour, minute: eventDate!.minute)
            : null;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: Text(
                "Edit Event",
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
                      decoration: _inputDecoration("Event Title", Icons.title),
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
                      context,
                      "Event Date",
                      updatedEventDate,
                      (date) {
                        setState(() => updatedEventDate = date);
                      },
                      Icons.event,
                    ),
                    const SizedBox(height: 15),
                    _buildTimePickerRow(
                      context,
                      "Event Time",
                      updatedEventTime,
                      (time) => setState(() => updatedEventTime = time),
                      Icons.access_time,
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: participantLimitController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration(
                        "Participant Limit (0 for unlimited)",
                        Icons.people,
                      ),
                    ),
                    if (currentParticipants > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Note: $currentParticipants people have already registered',
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontSize: 12,
                          ),
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
                        updatedEventDate == null ||
                        updatedEventTime == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Please fill all required fields"),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    final newEventDateTime = DateTime(
                      updatedEventDate!.year,
                      updatedEventDate!.month,
                      updatedEventDate!.day,
                      updatedEventTime!.hour,
                      updatedEventTime!.minute,
                    );

                    final parsedLimit =
                        int.tryParse(participantLimitController.text) ?? 0;
                    if (parsedLimit > 0 && parsedLimit < currentParticipants) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Participant limit cannot be less than current participants",
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    try {
                      await FirebaseFirestore.instance
                          .collection('events')
                          .doc(eventId)
                          .update({
                            'title': titleController.text,
                            'description': descriptionController.text,
                            'location': locationController.text,
                            'eventDateTime': newEventDateTime.toIso8601String(),
                            'participantLimit': parsedLimit,
                            'lastUpdatedAt': DateTime.now().toIso8601String(),
                          });

                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Event updated successfully!"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Error updating event: $e"),
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
  }

  void _showCancelEventDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text(
            "Cancel Event",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Are you sure you want to cancel '$title'?",
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                "This action cannot be undone and all registered participants will be notified.",
                style: TextStyle(color: Colors.red),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                "No, Keep Event",
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance
                      .collection('events')
                      .doc(eventId)
                      .update({
                        'status': 'cancelled',
                        'cancelledAt': DateTime.now().toIso8601String(),
                      });

                  Navigator.of(context).pop();
                  Navigator.of(context).pop(); // Close the event details too
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Event cancelled successfully"),
                      backgroundColor: Colors.orange,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Error cancelling event: $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text("Yes, Cancel Event"),
            ),
          ],
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
    BuildContext context,
    String label,
    DateTime? selectedDate,
    Function(DateTime) onDatePicked,
    IconData icon, {
    DateTime? minDate,
  }) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    return InkWell(
      onTap: () async {
        final DateTime minimumDate = minDate ?? DateTime.now();

        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: selectedDate ?? DateTime.now(),
          firstDate: minimumDate,
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
      },
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

  Widget _buildTimePickerRow(
    BuildContext context,
    String label,
    TimeOfDay? selectedTime,
    Function(TimeOfDay) onTimePicked,
    IconData icon,
  ) {
    return InkWell(
      onTap: () async {
        final TimeOfDay? picked = await showTimePicker(
          context: context,
          initialTime: selectedTime ?? TimeOfDay.now(),
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
          onTimePicked(picked);
        }
      },
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
                  selectedTime != null
                      ? selectedTime.format(context)
                      : "Select time",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                        selectedTime != null
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
}
