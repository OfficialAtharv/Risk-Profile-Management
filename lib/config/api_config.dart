import 'dart:io';

class ApiConfig {
  ApiConfig._();

  static const bool useEmulator = false;
  static const bool useLocalLan = false;

  static const String lanIp = '192.168.1.10';

  static const String ngrokUrl =
      'https://landmine-womanlike-outrage.ngrok-free.dev';

  static String get baseUrl {
    if (!useLocalLan) return ngrokUrl;

    if (Platform.isAndroid) {
      return useEmulator ? 'http://10.0.2.2:8000' : 'http://$lanIp:8000';
    }

    if (Platform.isIOS) return 'http://localhost:8000';

    return 'http://127.0.0.1:8000';
  }

  static String get visionAnalyze => '$baseUrl/api/vision/analyze';

  static String visionResult(String analysisId) =>
      '$baseUrl/api/vision/result/$analysisId';

  static String get docs => '$baseUrl/docs';
}