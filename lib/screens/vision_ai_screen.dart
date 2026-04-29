import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../services/vision_ai_service.dart';

class VisionAiScreen extends StatefulWidget {
  const VisionAiScreen({super.key});

  @override
  State<VisionAiScreen> createState() => _VisionAiScreenState();
}

class _VisionAiScreenState extends State<VisionAiScreen> {
  final VisionAiService _visionAiService = VisionAiService();

  File? _selectedVideo;
  String? _fileName;
  Duration? _videoDuration;
  bool _isAnalyzing = false;
  Map<String, dynamic>? _analysisResult;

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final controller = VideoPlayerController.file(file);

    await controller.initialize();
    final duration = controller.value.duration;
    await controller.dispose();

    if (duration.inSeconds > 60) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select video up to 1 minute only.')),
      );
      return;
    }

    setState(() {
      _selectedVideo = file;
      _fileName = result.files.single.name;
      _videoDuration = duration;
      _analysisResult = null;
    });
  }

  Future<void> _analyzeVideo() async {
    if (_selectedVideo == null || _isAnalyzing) return;

    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
    });

    try {
      final result = await _visionAiService.analyzeVideo(_selectedVideo!);

      if (!mounted) return;
      setState(() {
        _analysisResult = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _analysisResult = {
          "status": "failed",
          "summary": "Analysis failed. Please try again.",
          "overall_risk_level": "failed",
          "confidence_score": 0.0,
          "detected_events": [],
          "recommendation": e.toString(),
        };
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Color _riskColor(String value) {
    final risk = value.toLowerCase();

    if (risk.contains('very high')) return Colors.red;
    if (risk.contains('high')) return Colors.redAccent;
    if (risk.contains('medium')) return Colors.orangeAccent;
    if (risk.contains('low')) return Colors.green;
    if (risk.contains('yes')) return Colors.redAccent;
    if (risk.contains('no')) return Colors.green;
    if (risk.contains('clear')) return Colors.green;
    if (risk.contains('failed')) return Colors.redAccent;

    return Colors.grey;
  }

  double _confidenceValue(dynamic value) {
    if (value is int) return value / 100;
    if (value is double) return value > 1 ? value / 100 : value;
    return 0.0;
  }

  Widget _selectedVideoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: const Icon(Icons.video_file, size: 36),
        title: Text(
          _fileName ?? 'Selected Video',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'Duration: ${_videoDuration != null ? _formatDuration(_videoDuration!) : '--'}',
        ),
      ),
    );
  }

  Widget _resultDashboard() {
    final result = _analysisResult!;
    final status = result["status"]?.toString().toLowerCase() ?? "completed";
    final risk = result["overall_risk_level"]?.toString() ?? "unknown";
    final confidence = _confidenceValue(result["confidence_score"]);
    final events = result["detected_events"];
    final eventList = events is List ? events : [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: _riskColor(risk).withOpacity(0.15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                const Text(
                  'Overall Risk',
                  style: TextStyle(fontSize: 15, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  status == "failed" ? "FAILED" : risk.toUpperCase(),
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: _riskColor(status == "failed" ? "failed" : risk),
                  ),
                ),
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: confidence,
                  minHeight: 9,
                  borderRadius: BorderRadius.circular(20),
                ),
                const SizedBox(height: 8),
                Text(
                  'Confidence ${(confidence * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              result["summary"]?.toString() ?? "No summary returned.",
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
        ),

        const SizedBox(height: 16),

        const Text(
          'Detected Events',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),

        if (eventList.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No event data returned from AI.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          )
        else
          ...eventList.map((event) {
            final item = event is Map ? event : {};
            final name = item["name"]?.toString() ??
                item["type"]?.toString() ??
                "Driving Event";
            final value = item["value"]?.toString() ??
                item["severity"]?.toString() ??
                "not returned";

            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.warning_amber_rounded,
                  color: _riskColor(value),
                ),
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Status: $value'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _riskColor(value).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    value,
                    style: TextStyle(
                      color: _riskColor(value),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }),

        const SizedBox(height: 16),

        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.recommend, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    result["recommendation"]?.toString() ??
                        "No recommendation returned from AI.",
                    style: const TextStyle(fontSize: 15, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vision AI'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Upload Driver Video',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select a video up to 1 minute for Vision AI safety analysis.',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: _isAnalyzing ? null : _pickVideo,
              icon: const Icon(Icons.video_library),
              label: const Text('Select Video'),
            ),

            const SizedBox(height: 18),

            if (_selectedVideo != null) _selectedVideoCard(),

            const SizedBox(height: 18),

            ElevatedButton.icon(
              onPressed:
              (_selectedVideo != null && !_isAnalyzing) ? _analyzeVideo : null,
              icon: _isAnalyzing
                  ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.analytics),
              label: Text(_isAnalyzing ? 'Analyzing...' : 'Analyze Video'),
            ),

            const SizedBox(height: 24),

            if (_isAnalyzing)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Analyzing video... Please wait until the workflow completes.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            if (_analysisResult != null) _resultDashboard(),
          ],
        ),
      ),
    );
  }
}