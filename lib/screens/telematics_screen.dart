import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/telematics_service.dart';

class TelematicsScreen extends StatefulWidget {
  const TelematicsScreen({super.key});

  @override
  State<TelematicsScreen> createState() => _TelematicsScreenState();
}

class _TelematicsScreenState extends State<TelematicsScreen> {
  File? selectedFile;
  bool isLoading = false;
  Map<String, dynamic>? result;
  String? error;

  Future<void> pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
    );

    if (picked != null && picked.files.single.path != null) {
      setState(() {
        selectedFile = File(picked.files.single.path!);
        result = null;
        error = null;
      });
    }
  }

  Future<void> analyzeFile() async {
    if (selectedFile == null) {
      setState(() {
        error = 'Please select a CSV / Excel file first.';
      });
      return;
    }

    setState(() {
      isLoading = true;
      error = null;
      result = null;
    });

    final response =
    await TelematicsService.analyzeTelematicsFile(selectedFile!);

    setState(() {
      isLoading = false;

      if (response['success'] == true) {
        result = response;
      } else {
        error = response['error']?.toString() ?? 'Something went wrong';
      }
    });
  }

  Color getRiskColor(String riskLevel) {
    final value = riskLevel.toLowerCase();

    if (value.contains('low')) return Colors.green;
    if (value.contains('moderate')) return Colors.orange;
    if (value.contains('high')) return Colors.red;
    if (value.contains('critical')) return Colors.deepPurple;

    return Colors.blueGrey;
  }

  Widget infoCard(String title, String value, IconData icon) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSummary(Map<String, dynamic> summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Trip Summary',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        infoCard('Total Records', '${summary['total_records'] ?? '-'}',
            Icons.dataset),
        infoCard('Total Trip Distance',
            '${summary['total_trip_distance_km'] ?? '-'} km', Icons.route),
        infoCard('Average Speed', '${summary['average_speed'] ?? '-'} km/h',
            Icons.speed),
        infoCard('Maximum Speed', '${summary['maximum_speed'] ?? '-'} km/h',
            Icons.speed_outlined),
        infoCard(
            'Average Speeding',
            '${summary['average_speeding_percentage'] ?? '-'}%',
            Icons.warning_amber),
        infoCard(
            'Harsh Braking Events',
            '${summary['total_harsh_braking_events'] ?? '-'}',
            Icons.car_crash),
        infoCard(
            'Harsh Acceleration Events',
            '${summary['total_harsh_acceleration_events'] ?? '-'}',
            Icons.trending_up),
        infoCard('Lane Change Events',
            '${summary['total_lane_change_events'] ?? '-'}', Icons.alt_route),
        infoCard('Traffic Score', '${summary['average_traffic_score'] ?? '-'}',
            Icons.traffic),
        infoCard(
            'Road Risk Index',
            '${summary['average_road_risk_index'] ?? '-'}',
            Icons.add_road),
        infoCard(
            'Weather Risk Index',
            '${summary['average_weather_risk_index'] ?? '-'}',
            Icons.cloud),
        infoCard(
            'Reaction Delay',
            '${summary['average_reaction_delay_seconds'] ?? '-'} sec',
            Icons.timer),
      ],
    );
  }

  Widget buildConditions(Map<String, dynamic> conditions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Detected Conditions',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        infoCard('Traffic Condition',
            '${conditions['traffic_condition'] ?? '-'}', Icons.traffic),
        infoCard('Road Condition', '${conditions['road_condition'] ?? '-'}',
            Icons.add_road),
        infoCard('Weather Condition',
            '${conditions['weather_condition'] ?? '-'}', Icons.cloud),
      ],
    );
  }

  Widget buildRecommendations(List recommendations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recommendations',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...recommendations.map(
              (item) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle, color: Colors.blueAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.toString(),
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildResult() {
    if (result == null) return const SizedBox.shrink();

    final riskScore = result!['risk_score'] ?? '-';
    final driverScore = result!['driver_score'] ?? '-';
    final riskLevel = result!['risk_level']?.toString() ?? '-';

    final summary = result!['summary'] is Map<String, dynamic>
        ? result!['summary'] as Map<String, dynamic>
        : <String, dynamic>{};

    final conditions = result!['conditions'] is Map<String, dynamic>
        ? result!['conditions'] as Map<String, dynamic>
        : <String, dynamic>{};

    final recommendations = result!['recommendation'] is List
        ? result!['recommendation'] as List
        : [];

    final riskColor = getRiskColor(riskLevel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: riskColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: riskColor, width: 1.3),
          ),
          child: Column(
            children: [
              const Text(
                'Telematics Analysis Result',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 18),
              Text(
                '$riskScore',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: riskColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                riskLevel,
                style: TextStyle(
                  fontSize: 22,
                  color: riskColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Driver Score: $driverScore',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        buildSummary(summary),
        const SizedBox(height: 24),
        buildConditions(conditions),
        const SizedBox(height: 24),
        buildRecommendations(recommendations),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName = selectedFile?.path.split('/').last;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Telematics Analyzer'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.upload_file,
                      size: 46, color: Colors.blueAccent),
                  const SizedBox(height: 10),
                  const Text(
                    'Upload CSV / Excel Telematics File',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    fileName ?? 'No file selected',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: isLoading ? null : pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Choose File'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: isLoading ? null : analyzeFile,
                    icon: const Icon(Icons.analytics),
                    label: const Text('Analyze Telematics'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red),
                ),
                child: Text(
                  error!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            buildResult(),
          ],
        ),
      ),
    );
  }
}