import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class TelematicsService {
  // For Android physical phone, use your PC LAN IP.
  // Example: http://192.168.1.10:8001
  static const String baseUrl = 'http://127.0.0.1:8001';
  static const String analyzeUrl = '$baseUrl/api/telematics/analyze';

  static Future<Map<String, dynamic>> analyzeTelematicsFile(File file) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(analyzeUrl),
      );

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      final decoded = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return decoded;
      } else {
        throw Exception(decoded['detail'] ?? 'Telematics analysis failed');
      }
    } catch (e) {
      throw Exception('Telematics upload failed: $e');
    }
  }
}