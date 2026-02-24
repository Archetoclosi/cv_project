import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

class CloudinaryService {
  final String _cloudName = 'dyx6ocwe2';
  final String _uploadPreset = 'chatupload';

  Future<String?> uploadImage(Uint8List imageBytes) async {
    final url = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
    );

    final request = http.MultipartRequest('POST', url);
    request.fields['upload_preset'] = _uploadPreset;
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        imageBytes,
        filename: '${DateTime.now().millisecondsSinceEpoch}.jpg',
      ),
    );

    final response = await request.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      final data = jsonDecode(body);
      return data['secure_url'] as String;
    }
    
    debugPrint('Cloudinary error: $body');
    return null;
  }
}