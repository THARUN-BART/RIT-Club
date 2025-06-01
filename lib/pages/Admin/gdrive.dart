import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;

class GDriveImageHelper {
  static final RegExp _driveUrlPattern = RegExp(
    r'https?:\/\/drive\.google\.com\/file\/d\/([a-zA-Z0-9_-]+)',
  );

  static String? extractFileId(String url) {
    final match = _driveUrlPattern.firstMatch(url);
    return match?.group(1);
  }

  static String? convertToDirect(String url) {
    String? fileId = extractFileId(url);
    if (fileId != null) {
      return 'https://drive.google.com/uc?export=view&id=$fileId';
    }
    return null;
  }

  static Future<bool> verifyImageUrl(String url) async {
    try {
      String? directUrl = convertToDirect(url);
      if (directUrl == null) return false;

      final response = await http.head(Uri.parse(directUrl));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        String? contentType = response.headers['content-type'];
        return contentType != null && contentType.contains('image');
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

class GDriveImagePickerDialog extends StatefulWidget {
  const GDriveImagePickerDialog({Key? key}) : super(key: key);

  @override
  State<GDriveImagePickerDialog> createState() =>
      _GDriveImagePickerDialogState();
}

class _GDriveImagePickerDialogState extends State<GDriveImagePickerDialog> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String? _validImageUrl;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _validateUrl() async {
    if (_urlController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a Google Drive URL';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _validImageUrl = null;
    });

    try {
      String url = _urlController.text.trim();
      bool isValid = await GDriveImageHelper.verifyImageUrl(url);

      if (isValid) {
        setState(() {
          _validImageUrl = GDriveImageHelper.convertToDirect(url);
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'Invalid Google Drive image URL. Ensure the link is public.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error validating URL: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Google Drive Image'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              labelText: 'Google Drive URL',
              hintText: 'https://drive.google.com/file/d/...',
              errorText: _errorMessage,
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const CircularProgressIndicator()
          else if (_validImageUrl != null)
            CachedNetworkImage(
              imageUrl: _validImageUrl!,
              height: 120,
              width: 120,
              fit: BoxFit.cover,
              placeholder: (context, url) => const CircularProgressIndicator(),
              errorWidget:
                  (context, url, error) =>
                      const Icon(Icons.error, color: Colors.red, size: 50),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _validateUrl,
          child: const Text('Validate'),
        ),
      ],
    );
  }
}
