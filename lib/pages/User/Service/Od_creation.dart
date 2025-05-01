import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class LetterService {
  // Python API endpoint - replace with your actual deployed API URL
  static const String apiBaseUrl = 'https://your-api-url.com';

  static Future<Map<String, dynamic>> generateLetter({
    required String eventId,
    required String eventName,
    required DateTime eventDate,
  }) async {
    try {
      final FirebaseAuth auth = FirebaseAuth.instance;
      final FirebaseFirestore firestore = FirebaseFirestore.instance;

      final userId = auth.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Get user data
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw Exception('User document not found');
      }

      final userData = userDoc.data()!;
      final userName = userData['name'] ?? 'User';

      // Prepare API request
      final Map<String, dynamic> requestData = {
        'userId': userId,
        'userName': userName,
        'eventId': eventId,
        'eventName': eventName,
        'eventDate':
            eventDate.toIso8601String().split('T')[0], // Format: YYYY-MM-DD
      };

      // Call Python API
      final response = await http.post(
        Uri.parse('$apiBaseUrl/generate-letter'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestData),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to generate letter: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error in generateLetter: $e');
      rethrow;
    }
  }

  static Future<void> openLetterUrl(String url, BuildContext context) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the letter')),
        );
      }
    } catch (e) {
      debugPrint('Error opening letter URL: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error opening the letter')));
    }
  }

  // Function to check if a letter exists for an event
  static Future<String?> getLetterUrl(String userId, String eventId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final letterDoc =
          await firestore
              .collection('users')
              .doc(userId)
              .collection('eventLetters')
              .doc(eventId)
              .get();

      if (letterDoc.exists) {
        return letterDoc.data()?['letterUrl'];
      }
      return null;
    } catch (e) {
      debugPrint('Error getting letter URL: $e');
      return null;
    }
  }

  // Function to save a generated letter URL to Firestore
  static Future<void> saveLetterUrl(
    String userId,
    String eventId,
    String letterUrl,
  ) async {
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore
          .collection('users')
          .doc(userId)
          .collection('eventLetters')
          .doc(eventId)
          .set({
            'letterUrl': letterUrl,
            'createdAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      debugPrint('Error saving letter URL: $e');
      rethrow;
    }
  }
}

// Widget to display in the Event Card for letters
class EventLetterButton extends StatelessWidget {
  final String eventId;
  final String eventName;
  final DateTime eventDate;
  final bool isRegistrationEnded;

  const EventLetterButton({
    Key? key,
    required this.eventId,
    required this.eventName,
    required this.eventDate,
    required this.isRegistrationEnded,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isRegistrationEnded) return const SizedBox.shrink();

    return FutureBuilder<String?>(
      future: LetterService.getLetterUrl(
        FirebaseAuth.instance.currentUser!.uid,
        eventId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 36,
            width: 36,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }

        final letterUrl = snapshot.data;
        if (letterUrl != null) {
          // Letter exists - show view button
          return ElevatedButton.icon(
            onPressed: () => LetterService.openLetterUrl(letterUrl, context),
            icon: const Icon(Icons.visibility),
            label: const Text('View Letter'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          );
        } else {
          // No letter - show generate button
          return ElevatedButton.icon(
            onPressed: () => _generateLetter(context),
            icon: const Icon(Icons.description),
            label: const Text('Generate Letter'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          );
        }
      },
    );
  }

  Future<void> _generateLetter(BuildContext context) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Generating your letter...'),
                ],
              ),
            ),
      );

      // Generate letter
      final result = await LetterService.generateLetter(
        eventId: eventId,
        eventName: eventName,
        eventDate: eventDate,
      );

      // Close loading dialog
      Navigator.of(context).pop();

      if (result.containsKey('letterUrl')) {
        final letterUrl = result['letterUrl'];

        // Save the letter URL
        await LetterService.saveLetterUrl(
          FirebaseAuth.instance.currentUser!.uid,
          eventId,
          letterUrl,
        );

        // Show success dialog with option to view
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Letter Generated'),
                content: const Text(
                  'Your letter has been generated successfully.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      LetterService.openLetterUrl(letterUrl, context);
                    },
                    child: const Text('View Letter'),
                  ),
                ],
              ),
        );
      } else {
        // Show error dialog
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Error'),
                content: Text(
                  'Failed to generate letter: ${result['error'] ?? 'Unknown error'}',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
        );
      }
    } catch (e) {
      // Close loading dialog if still showing
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      // Show error message
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error generating letter: $e')));
    }
  }
}

// Complementary screen for managing all generated letters
class UserLettersScreen extends StatelessWidget {
  const UserLettersScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('Please log in to view your letters')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Event Letters')),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('eventLetters')
                .orderBy('createdAt', descending: true)
                .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final documents = snapshot.data?.docs ?? [];
          if (documents.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No letters generated yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'After event registration ends, you can generate letters',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final doc = documents[index];
              final data = doc.data() as Map<String, dynamic>;
              final letterUrl = data['letterUrl'] as String?;
              final timestamp = data['createdAt'] as Timestamp?;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: const Icon(Icons.article, color: Colors.blue),
                  title: FutureBuilder<DocumentSnapshot>(
                    future:
                        FirebaseFirestore.instance
                            .collection('events')
                            .doc(doc.id)
                            .get(),
                    builder: (context, eventSnapshot) {
                      if (eventSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Text('Loading event details...');
                      }

                      final eventData =
                          eventSnapshot.data?.data() as Map<String, dynamic>?;
                      return Text(eventData?['name'] ?? 'Unknown Event');
                    },
                  ),
                  subtitle:
                      timestamp != null
                          ? Text(
                            'Generated on ${_formatDate(timestamp.toDate())}',
                          )
                          : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.open_in_new),
                    onPressed:
                        letterUrl != null
                            ? () =>
                                LetterService.openLetterUrl(letterUrl, context)
                            : null,
                  ),
                  onTap:
                      letterUrl != null
                          ? () =>
                              LetterService.openLetterUrl(letterUrl, context)
                          : null,
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
