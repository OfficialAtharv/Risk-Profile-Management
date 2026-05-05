class ApiConfig {
  ApiConfig._();

  static const String lanIp = '192.168.1.52';

  static const String baseUrl = 'https://landmine-womanlike-outrage.ngrok-free.dev';

  static String get telematicsBaseUrl => 'http://127.0.0.1:8001';

  static String get visionAnalyze => '$baseUrl/api/vision/analyze';

  static String get telematicsAnalyze =>
      '$telematicsBaseUrl/api/telematics/analyze';

  static String get docs => '$baseUrl/docs';

  static String get telematicsDocs => '$telematicsBaseUrl/docs';
}