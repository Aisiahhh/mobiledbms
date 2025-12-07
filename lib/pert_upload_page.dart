// lib/pert_upload_page.dart
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

// conditional import: uses real File helper on platforms that support dart:io,
// and a stub on web so the app can compile for web.
import 'utils/io_file_stub.dart'
    if (dart.library.io) 'utils/io_file_io.dart' as io_file;

class PertUploadPage extends StatefulWidget {
  final PertMode? initialMode;
  const PertUploadPage({super.key, this.initialMode});

  @override
  State<PertUploadPage> createState() => _PertUploadPageState();
}

enum PertMode { original, revised }

class _PertUploadPageState extends State<PertUploadPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _contractorController = TextEditingController();
  final TextEditingController _projectController = TextEditingController();
  final TextEditingController _certifierNameController = TextEditingController();
  final TextEditingController _certifierDesignationController = TextEditingController();
  DateTime? _certificationDate;

  PertMode _mode = PertMode.original;
  bool _uploading = false;

  // IMPORTANT: on a physical device replace 10.0.2.2 with your machine IP e.g.
  // 'http://192.168.1.100:3000/pert' so the device can reach your server.
  final String _uploadUrl = kIsWeb ? 'http://localhost:3000/pert' : 'http://10.0.2.2:3000/pert';

  // PlatformFile references for each required doc (original)
  PlatformFile? _noticeOfAward;
  PlatformFile? _breakdownOfContractCost;
  PlatformFile? _constructionMethods;
  PlatformFile? _monthlyManpowerSchedule;

  // PlatformFile references for revised items
  PlatformFile? _prevApprovedSchedule;
  PlatformFile? _approvedOriginalContract;
  PlatformFile? _noticeToProceed;
  PlatformFile? _approvedVariationOrders;
  PlatformFile? _approvedTimeExtensions;
  PlatformFile? _latestPdmOrBarChart;

  static const int maxFileBytes = 25 * 1024 * 1024; // 25MB
  static const List<String> allowedExt = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'xlsx',
    'xls',
    'doc',
    'docx',
    'zip',
    'heic'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialMode != null) _mode = widget.initialMode!;
  }

  Future<PlatformFile?> _pickSingle() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (r == null) return null;
    final f = r.files.first;
    final ext = p.extension(f.name).replaceFirst('.', '').toLowerCase();
    if (f.size > maxFileBytes) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File too large (max 25MB)')));
      return null;
    }
    if (!allowedExt.contains(ext)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unsupported file type')));
      return null;
    }
    return f;
  }

  Future<void> _addPlatformFileToRequest(http.MultipartRequest req, String fieldName, PlatformFile pf) async {
    // web path: use bytes
    if (kIsWeb) {
      final bytes = pf.bytes;
      if (bytes == null) throw Exception('File bytes missing for web: ${pf.name}');
      req.files.add(http.MultipartFile.fromBytes(fieldName, bytes, filename: pf.name));
    } else {
      // native path: use File stream via conditional helper
      if (pf.path == null) throw Exception('PlatformFile.path is null for: ${pf.name}');
      final file = io_file.fileFromPath(pf.path!); // resolved to real File on native platforms
      final stream = http.ByteStream(file.openRead());
      final length = await file.length();
      req.files.add(http.MultipartFile(fieldName, stream, length, filename: p.basename(file.path)));
    }
  }

  Future<void> _submit() async {
    if (_formKey.currentState == null) return;
    if (!_formKey.currentState!.validate()) return;

    final missing = <String>[];
    if (_mode == PertMode.original) {
      if (_noticeOfAward == null) missing.add('Notice of Award');
      if (_breakdownOfContractCost == null) missing.add('Breakdown of Contract Cost');
      if (_constructionMethods == null) missing.add('Construction Methods');
      if (_monthlyManpowerSchedule == null) missing.add('Monthly Manpower and Equipment Schedule');
    } else {
      if (_prevApprovedSchedule == null) missing.add('Previously approved Construction Schedule + Manpower Schedule');
      if (_approvedOriginalContract == null) missing.add('Approved Original Contract');
      if (_noticeToProceed == null) missing.add('Notice to Proceed');
      if (_approvedVariationOrders == null) missing.add('Approved Variation Orders');
      if (_approvedTimeExtensions == null) missing.add('Approved Time Extensions (if any)');
      if (_latestPdmOrBarChart == null) missing.add('Latest PDM / Bar Chart with S-Curve');
    }

    if (missing.isNotEmpty) {
      final msg = 'Please attach: ' + missing.join(', ');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    setState(() {
      _uploading = true;
    });

    try {
      final uri = Uri.parse(_uploadUrl);
      final request = http.MultipartRequest('POST', uri);
      request.headers['Accept'] = 'application/json';

      final typeLabel = _mode == PertMode.original ? 'PERT/CPM/PDM — Original' : 'PERT/CPM/PDM — Revised';
      request.fields['type'] = typeLabel;
      request.fields['contractorName'] = _contractorController.text.trim();
      request.fields['projectName'] = _projectController.text.trim();
      request.fields['certifierName'] = _certifierNameController.text.trim();
      request.fields['certifierDesignation'] = _certifierDesignationController.text.trim();
      request.fields['certificationDate'] = _certificationDate?.toIso8601String() ?? '';

      if (_mode == PertMode.original) {
        await _addPlatformFileToRequest(request, 'pert_original_notice_of_award', _noticeOfAward!);
        await _addPlatformFileToRequest(request, 'pert_original_breakdown_of_contract_cost', _breakdownOfContractCost!);
        await _addPlatformFileToRequest(request, 'pert_original_construction_methods', _constructionMethods!);
        await _addPlatformFileToRequest(request, 'pert_original_monthly_manpower_schedule', _monthlyManpowerSchedule!);

        final meta = {
          'mode': 'original',
          'items': [
            {'label': 'Notice of Award', 'filename': _noticeOfAward!.name},
            {'label': 'Breakdown of Contract Cost', 'filename': _breakdownOfContractCost!.name},
            {'label': 'Construction Methods', 'filename': _constructionMethods!.name},
            {'label': 'Monthly Manpower and Equipment Schedule', 'filename': _monthlyManpowerSchedule!.name},
          ],
        };
        request.fields['pert_metadata'] = jsonEncode(meta);
      } else {
        await _addPlatformFileToRequest(request, 'pert_revised_prev_approved_schedule', _prevApprovedSchedule!);
        await _addPlatformFileToRequest(request, 'pert_revised_approved_original_contract', _approvedOriginalContract!);
        await _addPlatformFileToRequest(request, 'pert_revised_notice_to_proceed', _noticeToProceed!);
        await _addPlatformFileToRequest(request, 'pert_revised_approved_variation_orders', _approvedVariationOrders!);
        await _addPlatformFileToRequest(request, 'pert_revised_approved_time_extensions', _approvedTimeExtensions!);
        await _addPlatformFileToRequest(request, 'pert_revised_latest_pdm_bar_chart', _latestPdmOrBarChart!);

        final meta = {
          'mode': 'revised',
          'items': [
            {'label': 'Previously approved schedule + manpower', 'filename': _prevApprovedSchedule!.name},
            {'label': 'Approved Original Contract', 'filename': _approvedOriginalContract!.name},
            {'label': 'Notice to Proceed', 'filename': _noticeToProceed!.name},
            {'label': 'Approved Variation Orders', 'filename': _approvedVariationOrders!.name},
            {'label': 'Approved Time Extensions', 'filename': _approvedTimeExtensions!.name},
            {'label': 'Latest PDM / Bar Chart with S-Curve', 'filename': _latestPdmOrBarChart!.name},
          ],
        };
        request.fields['pert_metadata'] = jsonEncode(meta);
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PERT files uploaded successfully')));
        setState(() {
          _contractorController.clear();
          _projectController.clear();
          _certifierNameController.clear();
          _certifierDesignationController.clear();
          _certificationDate = null;

          _noticeOfAward = null;
          _breakdownOfContractCost = null;
          _constructionMethods = null;
          _monthlyManpowerSchedule = null;

          _prevApprovedSchedule = null;
          _approvedOriginalContract = null;
          _noticeToProceed = null;
          _approvedVariationOrders = null;
          _approvedTimeExtensions = null;
          _latestPdmOrBarChart = null;
        });
      } else {
        // show server error message if present (helps debugging)
        String body = response.body;
        String msg = 'Upload failed: ${response.statusCode}';
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map && decoded['error'] != null) msg += ' — ${decoded['error']}';
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _uploading = false;
      });
    }
  }

  Widget _buildOriginalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fileRow('Notice of Award', _noticeOfAward, () async {
          final f = await _pickSingle();
          if (f == null) return;
          setState(() {
            _noticeOfAward = f;
          });
        }),
        _fileRow('Breakdown of Contract Cost', _breakdownOfContractCost, () async {
          final f = await _pickSingle();
          if (f == null) return;
          setState(() {
            _breakdownOfContractCost = f;
          });
        }),
        _fileRow('Construction Methods', _constructionMethods, () async {
          final f = await _pickSingle();
          if (f == null) return;
          setState(() {
            _constructionMethods = f;
          });
        }),
        _fileRow('Monthly Manpower and Equipment Utilization Schedule', _monthlyManpowerSchedule, () async {
          final f = await _pickSingle();
          if (f == null) return;
          setState(() {
            _monthlyManpowerSchedule = f;
          });
        }),
      ],
    );
  }

  Widget _buildRevisedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fileRow('Previously approved Construction Schedule + Manpower Schedule', _prevApprovedSchedule, () async {
          final f = await _pickSingle();
          if (f == null) return;
          setState(() {
            _prevApprovedSchedule = f;
          });
        }),
        _fileRow('Approved Original Contract', _approvedOriginalContract, () async {
          final f = await _pickSingle();
          if (f == null) return;
          setState(() {
            _approvedOriginalContract = f;
          });
        }),
        _fileRow('Notice to Proceed', _noticeToProceed, () async {
          final f = await _pickSingle();
          if (f == null) return;
          setState(() {
            _noticeToProceed = f;
          });
        }),
        _fileRow('Approved Variation Orders', _approvedVariationOrders, () async {
          final f = await _pickSingle();
          if (f == null) return;
          setState(() {
            _approvedVariationOrders = f;
          });
        }),
        _fileRow('Approved Time Extensions (if any)', _approvedTimeExtensions, () async {
          final f = await _pickSingle();
          if (f == null) return;
          setState(() {
            _approvedTimeExtensions = f;
          });
        }),
        _fileRow('Latest PDM / Bar Chart with S-Curve', _latestPdmOrBarChart, () async {
          final f = await _pickSingle();
          if (f == null) return;
          setState(() {
            _latestPdmOrBarChart = f;
          });
        }),
      ],
    );
  }

  Widget _fileRow(String label, PlatformFile? file, VoidCallback onAttach) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(label),
        subtitle: file != null ? Text(file.name) : const Text('No file attached'),
        trailing: Wrap(spacing: 8, children: [
          TextButton.icon(onPressed: onAttach, icon: const Icon(Icons.attach_file), label: const Text('Attach')),
          if (file != null)
            IconButton(icon: const Icon(Icons.delete), onPressed: () {
              setState(() {
                switch (label) {
                  case 'Notice of Award':
                    _noticeOfAward = null;
                    break;
                  case 'Breakdown of Contract Cost':
                    _breakdownOfContractCost = null;
                    break;
                  case 'Construction Methods':
                    _constructionMethods = null;
                    break;
                  case 'Monthly Manpower and Equipment Utilization Schedule':
                    _monthlyManpowerSchedule = null;
                    break;
                  case 'Previously approved Construction Schedule + Manpower Schedule':
                    _prevApprovedSchedule = null;
                    break;
                  case 'Approved Original Contract':
                    _approvedOriginalContract = null;
                    break;
                  case 'Notice to Proceed':
                    _noticeToProceed = null;
                    break;
                  case 'Approved Variation Orders':
                    _approvedVariationOrders = null;
                    break;
                  case 'Approved Time Extensions (if any)':
                    _approvedTimeExtensions = null;
                    break;
                  case 'Latest PDM / Bar Chart with S-Curve':
                    _latestPdmOrBarChart = null;
                    break;
                  default:
                    break;
                }
              });
            }),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _contractorController.dispose();
    _projectController.dispose();
    _certifierNameController.dispose();
    _certifierDesignationController.dispose();
    super.dispose();
  }

  Future<void> _pickCertificationDate() async {
    final now = DateTime.now();
    final sel = await showDatePicker(context: context, initialDate: _certificationDate ?? now, firstDate: DateTime(2000), lastDate: DateTime(now.year + 3));
    if (sel != null) setState(() => _certificationDate = sel);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PERT / CPM / PDM Submission')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: RadioListTile<PertMode>(title: const Text('Original'), value: PertMode.original, groupValue: _mode, onChanged: (v) => setState(() => _mode = v!))),
              Expanded(child: RadioListTile<PertMode>(title: const Text('Revised'), value: PertMode.revised, groupValue: _mode, onChanged: (v) => setState(() => _mode = v!))),
            ]),
            const SizedBox(height: 8),
            TextFormField(controller: _contractorController, decoration: const InputDecoration(labelText: 'Contractor / Requestor Name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 8),
            TextFormField(controller: _projectController, decoration: const InputDecoration(labelText: 'Project Name / Contract No.'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 12),
            const Text('Required documents (attach files below)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_mode == PertMode.original) _buildOriginalSection() else _buildRevisedSection(),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Certification', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(controller: _certifierNameController, decoration: const InputDecoration(labelText: 'Print Name (Certifier)'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 8),
            TextFormField(controller: _certifierDesignationController, decoration: const InputDecoration(labelText: 'Designation'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
            const SizedBox(height: 8),
            ListTile(contentPadding: EdgeInsets.zero, title: const Text('Date'), subtitle: Text(_certificationDate != null ? _certificationDate!.toLocal().toString().split(' ')[0] : 'No date selected'), trailing: TextButton(onPressed: _pickCertificationDate, child: const Text('Pick date'))),
            const SizedBox(height: 16),
            ElevatedButton.icon(onPressed: _uploading ? null : _submit, icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload), label: Text(_uploading ? 'Uploading...' : 'Submit PERT Files'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14))),
            const SizedBox(height: 16),
            const Text('Notes:\n• All listed required documents must be attached for the chosen mode (Original / Revised).', style: TextStyle(fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
