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
  File? _selectedFile;
  String? _fileName;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _result;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
      allowMultiple: false,
    );

    if (result == null || result.files.single.path == null) return;

    setState(() {
      _selectedFile = File(result.files.single.path!);
      _fileName = result.files.single.name;
      _result = null;
    });
  }

  Future<void> _analyzeFile() async {
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select CSV / Excel file first")),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _result = null;
    });

    try {
      final response =
      await TelematicsService.analyzeTelematicsFile(_selectedFile!);

      setState(() {
        _result = response;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  Color _riskColor(String level) {
    final value = level.toLowerCase();

    if (value.contains("elite")) return Colors.teal;
    if (value.contains("safe")) return Colors.green;
    if (value.contains("moderate")) return Colors.orange;
    if (value.contains("high")) return Colors.deepOrange;
    if (value.contains("critical")) return Colors.red;

    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    final riskLevel = _result?["risk_level"]?.toString() ?? "Not Analyzed";
    final driverScore = _result?["driver_score"]?.toString() ?? "--";

    final summary = _result?["summary"];
    final conditions = _result?["conditions"];
    final drivers = _result?["drivers"];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Telematics Analysis"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _uploadCard(),
              const SizedBox(height: 18),

              if (_isAnalyzing)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),

              if (_result != null) ...[
                _scoreCard(driverScore, riskLevel),
                const SizedBox(height: 18),

                if (conditions is Map)
                  _conditionsCard(Map<String, dynamic>.from(conditions)),

                const SizedBox(height: 18),

                if (summary is Map)
                  _summaryTable(Map<String, dynamic>.from(summary)),

                const SizedBox(height: 18),

                if (drivers is List)
                  _driverTable(List<Map<String, dynamic>>.from(
                    drivers.map((e) => Map<String, dynamic>.from(e)),
                  )),

                const SizedBox(height: 18),

                _recommendationCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _uploadCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Upload Telematics File",
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Select CSV, XLS or XLSX file to analyze numeric driver risk.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _isAnalyzing ? null : _pickFile,
              icon: const Icon(Icons.upload_file),
              label: const Text("Choose File"),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _fileName!,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _isAnalyzing ? null : _analyzeFile,
              icon: const Icon(Icons.analytics),
              label: Text(_isAnalyzing ? "Analyzing..." : "Analyze File"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scoreCard(String score, String riskLevel) {
    final color = _riskColor(riskLevel);

    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.90),
              color.withOpacity(0.60),
            ],
          ),
        ),
        child: Column(
          children: [
            const Text(
              "Driver Risk Score",
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              score,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                riskLevel,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _conditionsCard(Map<String, dynamic> conditions) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Driving Conditions",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            _conditionTile(Icons.traffic, "Traffic",
                conditions["traffic_condition"]?.toString() ?? "-"),
            _conditionTile(Icons.route, "Road",
                conditions["road_condition"]?.toString() ?? "-"),
            _conditionTile(Icons.cloud, "Weather",
                conditions["weather_condition"]?.toString() ?? "-"),
          ],
        ),
      ),
    );
  }

  Widget _conditionTile(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(value),
        ],
      ),
    );
  }

  Widget _summaryTable(Map<String, dynamic> summary) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Analysis Summary",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            Table(
              border: TableBorder.all(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(8),
              ),
              columnWidths: const {
                0: FlexColumnWidth(1.5),
                1: FlexColumnWidth(1),
              },
              children: summary.entries.map((entry) {
                return TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        _formatKey(entry.key),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(entry.value.toString()),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _driverTable(List<Map<String, dynamic>> drivers) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Driver-wise Result",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text("Driver")),
                  DataColumn(label: Text("Score")),
                  DataColumn(label: Text("Risk")),
                  DataColumn(label: Text("Speeding %")),
                  DataColumn(label: Text("Brake")),
                  DataColumn(label: Text("Accel")),
                  DataColumn(label: Text("Lane")),
                ],
                rows: drivers.map((driver) {
                  return DataRow(
                    cells: [
                      DataCell(Text(driver["driver_id"].toString())),
                      DataCell(Text(driver["driver_score"].toString())),
                      DataCell(Text(driver["risk_level"].toString())),
                      DataCell(Text(driver["speeding_percentage"].toString())),
                      DataCell(Text(driver["harsh_braking_events"].toString())),
                      DataCell(Text(driver["harsh_acceleration_events"].toString())),
                      DataCell(Text(driver["lane_change_events"].toString())),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recommendationCard() {
    final recommendations = _result?["recommendation"];

    if (recommendations == null) return const SizedBox();

    final items = recommendations is List
        ? recommendations
        : [recommendations.toString()];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Recommendations",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...items.map(
                  (item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.toString())),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatKey(String key) {
    return key
        .replaceAll("_", " ")
        .split(" ")
        .map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    })
        .join(" ");
  }
}