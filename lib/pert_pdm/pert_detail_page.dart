// lib/pert_detail_page.dart - Simplified version
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class PertDetailPage extends StatefulWidget {
  final String uploadId;
  final String serverUrl;

  const PertDetailPage({
    super.key,
    required this.uploadId,
    required this.serverUrl,
  });

  @override
  State<PertDetailPage> createState() => _PertDetailPageState();
}

class _PertDetailPageState extends State<PertDetailPage> {
  Map<String, dynamic>? _upload;
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final uri = Uri.parse('${widget.serverUrl}/pert/${widget.uploadId}');
      final resp = await http.get(uri);

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final Map<String, dynamic> data = jsonDecode(resp.body);
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Failed to load details');
      }

      // Use safe type conversion
      setState(() {
        _upload = _convertToMap(data['upload']);
        
        if (data['files'] is List) {
          _files = (data['files'] as List)
              .map((item) => _convertToMap(item))
              .where((map) => map.isNotEmpty)
              .toList();
        } else {
          _files = [];
        }
        
        _loading = false;
      });
    } catch (e) {
      print('Error loading PERT details: $e');
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _convertToMap(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }

  Future<void> _launchFile(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open file')),
      );
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return 'Not set';
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (e) {
      return iso;
    }
  }

  Widget _buildInfoCard(String title, String content) {
    return Card(
      child: ListTile(
        title: Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        subtitle: Text(content.isNotEmpty ? content : 'Not provided'),
      ),
    );
  }

  Widget _buildFileCard(Map<String, dynamic> file) {
    final filename = file['filename']?.toString() ?? 'Unknown file';
    final label = file['label']?.toString();
    final docType = file['doc_type']?.toString();
    final signedUrl = file['signedUrl']?.toString();

    return Card(
      child: ListTile(
        leading: const Icon(Icons.insert_drive_file),
        title: Text(filename),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null && label.isNotEmpty) Text(label),
            if (docType != null && docType.isNotEmpty)
              Chip(
                label: Text(docType),
                labelStyle: const TextStyle(fontSize: 10),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
        trailing: signedUrl != null
            ? IconButton(
                icon: const Icon(Icons.download),
                onPressed: () => _launchFile(signedUrl),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PERT Submission Details'),
        actions: [
          IconButton(
            onPressed: _loadDetails,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 64),
                        const SizedBox(height: 16),
                        Text('Error: $_error'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadDetails,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Card(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _upload?['project_name']?.toString() ?? 'No Project Name',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _upload?['contractor_name']?.toString() ?? 'No Contractor',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Chip(
                                label: Text(
                                  _upload?['upload_type']?.toString() ?? 'PERT',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                backgroundColor: Theme.of(context).primaryColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Submission Info
                      const Text(
                        'Submission Information',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildInfoCard('Contractor', _upload?['contractor_name']?.toString() ?? ''),
                      _buildInfoCard('Project', _upload?['project_name']?.toString() ?? ''),
                      if (_upload?['certifier_name'] != null)
                        _buildInfoCard('Certified by', _upload?['certifier_name']?.toString() ?? ''),
                      if (_upload?['certifier_designation'] != null)
                        _buildInfoCard('Designation', _upload?['certifier_designation']?.toString() ?? ''),
                      if (_upload?['certification_date'] != null)
                        _buildInfoCard('Certification Date', _formatDate(_upload?['certification_date']?.toString())),
                      _buildInfoCard('Created', _formatDate(_upload?['created_at']?.toString())),
                      const SizedBox(height: 24),
                      // Files Section
                      Row(
                        children: [
                          const Text(
                            'Attached Files',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text('${_files.length} files'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_files.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: Text('No files attached'),
                            ),
                          ),
                        )
                      else
                        Column(
                          children: _files.map(_buildFileCard).toList(),
                        ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }
}