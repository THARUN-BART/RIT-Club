class Event {
  final String id;
  final String title;
  final String? description;
  final DateTime eventDateTime;
  final DateTime? registrationEndDate;
  final String? location;
  final String? clubName;
  final String status; // 'active' or 'past'

  Event({
    required this.id,
    required this.title,
    this.description,
    required this.eventDateTime,
    this.registrationEndDate,
    this.location,
    this.clubName,
    required this.status,
  });

  factory Event.fromFirestore(String id, Map<String, dynamic> data) {
    return Event(
      id: id,
      title: data['title'] ?? 'No Title',
      description: data['description'],
      eventDateTime: data['eventDateTime']?.toDate() ?? DateTime.now(),
      registrationEndDate: data['registrationEndDate']?.toDate(),
      location: data['location'],
      clubName: data['clubName'],
      status: data['status'] ?? 'active',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'eventDateTime': eventDateTime,
      'registrationEndDate': registrationEndDate,
      'location': location,
      'clubName': clubName,
      'status': status,
    };
  }
}
