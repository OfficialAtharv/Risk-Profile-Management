import 'dart:io';

class ApiConfig {
  ApiConfig._();

  static const bool useNgrok = true;

  static const String lanIp = '192.168.0.144';

  static const String ngrokUrl =
      'https://landmine-womanlike-outrage.ngrok-free.dev';

  static String get baseUrl {
    if (useNgrok) return ngrokUrl;

    if (Platform.isAndroid) {
      return 'http://$lanIp:8000';
    }

    if (Platform.isIOS) {
      return 'http://localhost:8000';
    }

    return 'http://127.0.0.1:8000';
  }

  static String get visionAnalyze => '$baseUrl/api/vision/analyze';

  static String visionResult(String analysisId) =>
      '$baseUrl/api/vision/result/$analysisId';

  static String get docs => '$baseUrl/docs';
}