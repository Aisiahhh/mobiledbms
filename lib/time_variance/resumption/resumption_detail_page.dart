// lib/resumption_detail_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_dbms/models/resumption_models.dart';
import 'package:url_launcher/url_launcher.dart';

class ResumptionDetailPage extends StatefulWidget {
  final String uploadId; // UUID string
  final String serverUrl;

  const ResumptionDetailPage({
    super.key,
    required this.uploadId,
    required this.serverUrl,
  });

  @override
  State<ResumptionDetailPage> createState() => _ResumptionDetailPageState();
}

class _ResumptionDetailPageState extends State<ResumptionDetailPage> {
  ResumptionUpload? _upload;
  List<SupportingFile> _files = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchUploadDetails();
  }

  Future<void> _fetchUploadDetails() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final encodedId = Uri.encodeComponent(widget.uploadId);
      final uri = Uri.parse('${widget.serverUrl}/resumption/$encodedId');

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          final responseObj = UploadDetailResponse.fromJson(Map<String, dynamic>.from(data));
          setState(() {
            _upload = responseObj.upload;
            _files = responseObj.files;
            _hasError = false;
          });
        } else {
          throw Exception('Unexpected response structure: ${response.body}');
        }
      } else {
        throw Exception('Failed to load upload details: ${response.statusCode} — ${response.body}');
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshDetails() async {
    await _fetchUploadDetails();
  }

  Future<void> _openFile(SupportingFile file) async {
    final url = file.signedUrl ?? file.storagePath;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File URL not available')),
      );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid file URL')),
      );
      return;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open: ${file.filename}')),
      );
    }
  }

  // Helper: return required files (doc_type == 'required')
  List<SupportingFile> get _requiredFiles =>
      _files.where((f) => (f.docType ?? '').toLowerCase() == 'required').toList();

  // Helper: group non-required files by doc_type
  Map<String, List<SupportingFile>> get _groupedSupportFiles {
    final map = <String, List<SupportingFile>>{};
    for (final f in _files) {
      final dt = (f.docType ?? '').trim();
      if (dt.isEmpty || dt.toLowerCase() == 'required') continue;
      map.putIfAbsent(dt, () => []).add(f);
    }
    return map;
  }

  Widget _buildFileTile(SupportingFile file) {
    final icon = _getFileIcon(file.filename);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: Icon(icon, color: Colors.blue),
      title: Text(file.filename, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (file.label != null && file.label!.isNotEmpty) Text('Label: ${file.label}'),
          if (file.caption != null && file.caption!.isNotEmpty) Text('Caption: ${file.caption}'),
          if (file.station != null && file.station!.isNotEmpty) Text('Station: ${file.station}'),
          if (file.latitude != null && file.longitude != null)
            Text('Location: ${file.latitude}, ${file.longitude}'),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.open_in_new),
        onPressed: () => _openFile(file),
      ),
      onTap: () => _openFile(file),
    );
  }

  Widget _buildRequiredSection() {
    final req = _requiredFiles;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.verified_user, color: Colors.green),
        title: Text('Required Documents (${req.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
        children: req.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No required documents uploaded.', style: TextStyle(color: Colors.grey)),
                )
              ]
            : req.map((f) => _buildFileTile(f)).toList(),
      ),
    );
  }

  Widget _buildSupportingSection() {
    final grouped = _groupedSupportFiles;
    final keys = grouped.keys.toList()..sort((a, b) => a.compareTo(b));

    if (grouped.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: ListTile(
          leading: const Icon(Icons.folder_open, color: Colors.grey),
          title: const Text('Supporting Documents'),
          subtitle: const Text('No supporting documents uploaded.'),
        ),
      );
    }

    return Column(
      children: keys.map((docType) {
        final list = grouped[docType]!;
        final title = _getFileType(docType);
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: ExpansionTile(
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.blue.withOpacity(0.12),
              child: Text(docType, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
            ),
            title: Text('$title (${list.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            children: list.map((f) => _buildFileTile(f)).toList(),
          ),
        );
      }).toList(),
    );
  }

  IconData _getFileIcon(String filename) {
    final parts = filename.toLowerCase().split('.');
    final ext = parts.isNotEmpty ? parts.last : '';
    if (ext == 'pdf') return Icons.picture_as_pdf;
    if (['jpg', 'jpeg', 'png', 'gif', 'heic'].contains(ext)) return Icons.image;
    if (['doc', 'docx'].contains(ext)) return Icons.description;
    if (['xls', 'xlsx', 'csv'].contains(ext)) return Icons.table_chart;
    return Icons.insert_drive_file;
  }

  // Friendly titles for doc_type keys like 'A'..'M' and 'required' fallback
  String _getFileType(String docType) {
    final key = docType.trim();
    if (key.toLowerCase() == 'required') return 'Required Document';

    final titles = {
      'A': 'Due to Rainy/Unworkable Days',
      'B': 'Due to Delay in payment',
      'C': 'Due to Road Right-of-Way Problem',
      'D': 'Due to Peace and Order Condition',
      'E': 'Due to Inaccessibility to Project',
      'F': 'Due to Obstruction',
      'G': 'Due to Failure of Government to provide plans/drawings',
      'H': 'Due to non-availability of construction materials',
      'I': 'Due to effect of Force Majeure',
      'J': 'Due to absence of MMDA Permit/Clearance',
      'K': 'Due to absence of LGU Permit/Clearance',
      'L': 'Due to DENR Clearance/Permit',
      'M': 'Delayed delivery of Imported Materials',
    };

    return titles[key] ?? docType;
  }

  Widget _buildInfoCard() {
    if (_upload == null) return Container();

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildInfoRow('Project', _upload!.projectName),
          _buildInfoRow('Contractor', _upload!.contractorName),
          _buildInfoRow('Upload Type', _upload!.uploadType),
          if (_upload!.notes != null && _upload!.notes!.isNotEmpty) _buildInfoRow('Notes', _upload!.notes!),
          _buildInfoRow('Uploaded', _formatDate(_upload!.createdAt)),
        ]),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 120,
          child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
      ]),
    );
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_upload?.projectName.isNotEmpty == true ? _upload!.projectName : 'Upload Details'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshDetails, tooltip: 'Refresh'),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasError) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text('Error loading details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Text(_errorMessage, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _refreshDetails, child: const Text('Try Again')),
        ]),
      );
    }

    if (_upload == null) {
      return const Center(child: Text('No upload found'));
    }

    return RefreshIndicator(
      onRefresh: _refreshDetails,
      child: ListView(
        children: [
          _buildInfoCard(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text('Documents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          // Required documents (separate)
          _buildRequiredSection(),
          const SizedBox(height: 8),
          // Supporting / grouped documents
          _buildSupportingSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
