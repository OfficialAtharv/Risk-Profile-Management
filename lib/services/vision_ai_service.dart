import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class VisionAiService {
  Future<Map<String, dynamic>> analyzeVideo(File videoFile) async {
    try {
      if (!await videoFile.exists()) {
        throw Exception("Selected video file does not exist.");
      }

      print("========== VISION AI DEBUG ==========");
      print("Video path: ${videoFile.path}");
      print("Video size: ${await videoFile.length()} bytes");
      print("Analyze API: ${ApiConfig.visionAnalyze}");
      print("=====================================");

      final request = http.MultipartRequest(
        "POST",
        Uri.parse(ApiConfig.visionAnalyze),
      );

      // ✅ IMPORTANT: backend expects "video"
      request.files.add(
        await http.MultipartFile.fromPath("video", videoFile.path),
      );

      request.fields["prompt"] = _analysisPrompt;

      final streamedResponse =
      await request.send().timeout(const Duration(minutes: 5));

      final response = await http.Response.fromStream(streamedResponse);

      print("========== BACKEND RESPONSE ==========");
      print("Status: ${response.statusCode}");
      print("Body: ${response.body}");
      print("======================================");

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception("Backend error ${response.statusCode}: ${response.body}");
      }

      final decoded = jsonDecode(response.body);

      return _normalizeResult(decoded);
    } catch (e) {
      throw Exception("Analysis failed: $e");
    }
  }

  Map<String, dynamic> _normalizeResult(dynamic responseData) {
    final source = _extractFinalResult(responseData);

    final riskScore = _readScore(source["risk_score"]);
    final riskBand =
        source["risk_band"]?.toString() ?? "unknown";

    return {
      "analysis_id": _findValue(responseData, "analysis_id"),
      "status": "completed",
      "summary": source["summary"]?.toString() ?? "No summary returned.",
      "overall_risk_level": riskBand,
      "confidence_score": riskScore != null ? riskScore / 100 : 0.0,
      "detected_events": [
        {
          "name": "Harsh Acceleration",
          "value": source["harsh_acceleration"]?.toString() ?? "unknown",
        },
        {
          "name": "Harsh Braking",
          "value": source["harsh_braking"]?.toString() ?? "unknown",
        },
        {
          "name": "Over Speeding",
          "value": source["over_speeding"]?.toString() ?? "unknown",
        },
        {
          "name": "Road Condition",
          "value": source["road_condition"]?.toString() ?? "unknown",
        },
        {
          "name": "Collision Alert",
          "value": source["collision_alert"]?.toString() ?? "unknown",
        },
      ],
      "recommendation":
      source["recommendation"]?.toString() ?? "No recommendation returned.",
      "raw_result": source,
    };
  }

  Map<String, dynamic> _extractFinalResult(dynamic data) {
    dynamic current = data;

    if (current is List && current.isNotEmpty) {
      current = current.first;
    }

    while (current is Map<String, dynamic>) {
      if (_hasRiskFields(current)) {
        return current;
      }

      final result = current["result"];

      if (result is Map<String, dynamic>) {
        current = result;
        continue;
      }

      if (result is List && result.isNotEmpty) {
        current = result.first;
        continue;
      }

      if (result is String) {
        final parsed = _tryParseJsonFromText(result);
        if (parsed != null) {
          current = parsed;
          continue;
        }
      }

      final rawText = current["raw_text"];
      if (rawText is String) {
        final parsed = _tryParseJsonFromText(rawText);
        if (parsed != null) return parsed;
      }

      break;
    }

    return current is Map<String, dynamic> ? current : {};
  }

  bool _hasRiskFields(Map<String, dynamic> map) {
    return map.containsKey("risk_score") ||
        map.containsKey("risk_band") ||
        map.containsKey("harsh_acceleration") ||
        map.containsKey("harsh_braking") ||
        map.containsKey("over_speeding") ||
        map.containsKey("road_condition") ||
        map.containsKey("collision_alert");
  }

  dynamic _findValue(dynamic data, String key) {
    if (data is Map<String, dynamic>) {
      if (data.containsKey(key)) return data[key];

      final result = data["result"];
      if (result != null) return _findValue(result, key);
    }

    if (data is List && data.isNotEmpty) {
      return _findValue(data.first, key);
    }

    return null;
  }

  Map<String, dynamic>? _tryParseJsonFromText(String text) {
    try {
      final cleaned = text
          .replaceAll("```json", "")
          .replaceAll("```", "")
          .trim();

      final decoded = jsonDecode(cleaned);

      if (decoded is Map<String, dynamic>) return decoded;

      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        return Map<String, dynamic>.from(decoded.first);
      }
    } catch (_) {}

    return null;
  }

  int? _readScore(dynamic value) {
    if (value == null) return null;
    if (value is int) return value.clamp(0, 100);
    if (value is double) return value.round().clamp(0, 100);
    return int.tryParse(value.toString())?.clamp(0, 100);
  }

  static const String _analysisPrompt = """
Analyze this dashcam driving video.

Return ONLY valid JSON. Do not use markdown.

{
  "risk_score": 0,
  "risk_band": "low/medium/high/very high",
  "harsh_acceleration": "yes/no/unknown",
  "harsh_braking": "yes/no/unknown",
  "over_speeding": "yes/no/unknown",
  "road_condition": "clear/wet/rough/traffic/unknown",
  "collision_alert": "low/medium/high/unknown",
  "summary": "short 2 line summary",
  "recommendation": "short safety recommendation"
}
""";
}