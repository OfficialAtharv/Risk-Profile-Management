import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class TelematicsService {
  static Future<Map<String, dynamic>> analyzeTelematicsFile(File file) async {
    try {
      final uri = Uri.parse(ApiConfig.telematicsAnalyze);

      print('========== TELEMATICS REQUEST ==========');
      print('URL: $uri');
      print('FILE: ${file.path}');
      print('EXISTS: ${await file.exists()}');
      print('SIZE: ${await file.length()} bytes');
      print('=======================================');

      final request = http.MultipartRequest('POST', uri);

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
        ),
      );

      final streamedResponse = await request
          .send()
          .timeout(const Duration(seconds: 120));

      final response = await http.Response.fromStream(streamedResponse);

      print('========== TELEMATICS RESPONSE ==========');
      print('STATUS: ${response.statusCode}');
      print('BODY: ${response.body}');
      print('========================================');

      dynamic decoded;

      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        return {
          'success': false,
          'error': 'Invalid backend response: ${response.body}',
        };
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }

        return {
          'success': true,
          'data': decoded,
        };
      }

      return {
        'success': false,
        'error': decoded is Map
            ? decoded['detail']?.toString() ??
            decoded['message']?.toString() ??
            'Telematics analysis failed'
            : 'Telematics analysis failed',
      };
    } on SocketException catch (e) {
      return {
        'success': false,
        'error':
        'Backend not reachable. Start telematics backend on port 8001 and check IP. Details: $e',
      };
    } on HttpException catch (e) {
      return {
        'success': false,
        'error': 'HTTP error: $e',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}