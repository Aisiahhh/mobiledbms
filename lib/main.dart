// lib/main.dart
import 'dart:convert';
import 'dart:io' show File; // NOTE: this import breaks Flutter web builds. See note below.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contract Uploads',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  final List<_Option> options = const [
    _Option('Variation Order', Icons.edit_note),
    _Option('Resumption', Icons.play_circle_fill),
    _Option('Suspension', Icons.pause_circle_filled),
    _Option('Time Extension', Icons.timer),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Documents')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: GridView.builder(
          itemCount: options.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, childAspectRatio: 1.05, crossAxisSpacing: 12, mainAxisSpacing: 12),
          itemBuilder: (context, idx) {
            final opt = options[idx];
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => UploadPage(uploadType: opt.title)),
                );
              },
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(opt.icon, size: 48),
                    const SizedBox(height: 8),
                    Text(opt.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Option {
  final String title;
  final IconData icon;
  const _Option(this.title, this.icon);
}

/// Human-friendly titles for A..M
final Map<String, String> additionalTitles = {
  'A': 'Due to Rainy/Unworkable Days considered unfavorable for prosecution of the works at the site',
  'B': 'Due to Delay in payment of Contractor’s Claim for Progress Billing/s',
  'C': 'Due to Road Right-of-Way (RROW) Problem',
  'D': 'Due to Peace and Order Condition',
  'E': 'Due to Inaccessibility to Project',
  'F': 'Due to Obstruction',
  'G': 'Due to Failure of Government to provide necessary construction plans/drawings',
  'H': 'Due to non-availability of construction materials',
  'I': 'Due to effect of Force Majeure',
  'J': 'Due to absence of MMDA Permit/Clearance for Road Repair/Excavation/Traffic Clearance',
  'K': 'Due to absence of LGU Permit/Clearance/Homeowners Association Clearance/Permit',
  'L': 'Due to DENR Clearance/Permit to cut/remove trees/Coconut within the RROW',
  'M': 'Delayed delivery of Imported Materials due to truck ban and/or port congestion',
};

/// Map of additional document types (A..M) to list of required checklist labels.
final Map<String, List<String>> additionalRequirements = {
  'A': [
    'Geotagged pictures (with caption) showing that the site is workable',
  ],
  'B': [
    'Certified copy of Vouchers/Progress Billings',
    'Certification from the Accounting Division of payments received',
  ],
  'C': [
    'Geotagged pictures before and after RROW problem resolved',
    'Certification from the Barangay Captain/Mayor that RROW Problem was resolved',
  ],
  'D': [
    'Certification from PNP station commander and confirmation by the DILG Regional Director',
  ],
  'E': [
    'Geotagged pictures showing resolution of inaccessibility',
    'Relevant document proving inaccessibility was resolved',
  ],
  'F': [
    'Geotagged pictures showing obstruction removed',
    'Relevant documents (permit, communication letters, minutes of meeting)',
  ],
  'G': [
    'Proof of date of approval of construction plan/drawings',
  ],
  'H': [
    'Certification from DTI and suppliers that materials are available',
  ],
  'I': [
    'Pictures showing effect of force majeure addressed for Resumption Order',
    'Relevant documents (communication letters, minutes of meeting)',
  ],
  'J': [
    'Contractor request duly received by the Implementing Office for Resumption',
    'Copy of the MMDA Permit/Clearance for Road Repair/Excavation/Traffic Clearance',
  ],
  'K': [
    'Contractor request duly received by the Implementing Office for Resumption',
    'Copy of the LGU Permit/Clearance/Re-blocking permit/clearance',
  ],
  'L': [
    'Contractor request duly received by the Implementing Office for Resumption',
    'Copy of DENR Clearance/Permit to cut/remove trees',
    'PCA Clearance (for Coconut)',
  ],
  'M': [
    'Contractor request to the Implementing Office for Resumption',
    'Certified true copy of Bill of Lading',
    'Original copy of Custom Clearance',
    'Certification from the Implementing Office that delayed delivery was resolved',
  ],
};

/// Per-file item that includes PlatformFile and metadata
class SupportFileItem {
  final PlatformFile file;
  final String? station;
  final String? caption;
  final double? lat;
  final double? lon;

  SupportFileItem({
    required this.file,
    this.station,
    this.caption,
    this.lat,
    this.lon,
  });
}

/// Model to hold a supporting document (type A..M) and its attached files per requirement
class SupportingDoc {
  final String type; // 'A'
  final String title; // friendly name
  final Map<String, SupportFileItem> filesByLabel; // label -> file item
  SupportingDoc({required this.type, required this.title, required this.filesByLabel});
}

class UploadPage extends StatefulWidget {
  final String uploadType;
  const UploadPage({super.key, required this.uploadType});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _contractorController = TextEditingController();
  final TextEditingController _projectController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  // Required resumption files (explicit)
  PlatformFile? _reqLetterRequest;
  PlatformFile? _reqApprovedSuspension;
  PlatformFile? _reqCertifiedContract;

  // Supporting docs A..M
  final List<SupportingDoc> _supportingDocs = [];

  bool _uploading = false;

  // IMPORTANT: set your upload server URL here
  // - Android emulator (AVD): use 10.0.2.2
  // - iOS simulator: use localhost
  // - physical device: use your machine IP (e.g., http://192.168.1.45:3000)
  // - production: use your publicly reachable HTTPS URL
  // Example for Android emulator:
  // final String _serverUploadUrl = 'http://10.0.2.2:3000/upload';
  // For iOS simulator:
  // final String _serverUploadUrl = 'http://localhost:3000/upload';
  final String _serverUploadUrl = kIsWeb ? 'http://localhost:3000/upload' : 'http://10.0.2.2:3000/upload';

  Future<PlatformFile?> _pickSingleFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, withData: true);
    if (result == null) return null;
    return result.files.first;
  }

  Future<void> _pickRequiredFile(int slot) async {
    final f = await _pickSingleFile();
    if (f == null) return;
    setState(() {
      if (slot == 1) _reqLetterRequest = f;
      if (slot == 2) _reqApprovedSuspension = f;
      if (slot == 3) _reqCertifiedContract = f;
    });
  }

  Future<Map<String, double>> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied.');
    }

    final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
    return {'lat': pos.latitude, 'lon': pos.longitude};
  }

  Future<SupportFileItem?> _pickFileWithMetadata(String label) async {
    final picked = await _pickSingleFile();
    if (picked == null) return null;

    final stationCtrl = TextEditingController();
    final captionCtrl = TextEditingController();
    final latCtrl = TextEditingController();
    final lonCtrl = TextEditingController();

    final completed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setStateDialog) {
          Future<void> tryAutoFill() async {
            setStateDialog(() {});
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            final snack = ScaffoldMessenger.of(context);
            snack.showSnackBar(const SnackBar(content: Text('Attempting to get current location...')));
            try {
              final coords = await _determinePosition();
              latCtrl.text = coords['lat']!.toString();
              lonCtrl.text = coords['lon']!.toString();
              snack.hideCurrentSnackBar();
              snack.showSnackBar(const SnackBar(content: Text('Location auto-filled')));
              setStateDialog(() {});
            } catch (e) {
              snack.hideCurrentSnackBar();
              snack.showSnackBar(SnackBar(content: Text('Could not get location: $e')));
            }
          }

          return AlertDialog(
            title: Text('Attach file and add metadata'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file),
                    title: Text(picked.name),
                    subtitle: Text('Label: $label'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: stationCtrl,
                    decoration: const InputDecoration(labelText: 'Station (e.g., Station 10)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: captionCtrl,
                    decoration: const InputDecoration(labelText: 'Caption (photo description)'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: latCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                        decoration: const InputDecoration(labelText: 'Latitude (optional)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: lonCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                        decoration: const InputDecoration(labelText: 'Longitude (optional)'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await tryAutoFill();
                    },
                    icon: const Icon(Icons.my_location),
                    label: const Text('Auto-fill current location'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'If auto-fill fails, you can manually paste latitude and longitude or continue without coordinates.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
            ],
          );
        });
      },
    );

    if (completed != true) return null;

    double? lat;
    double? lon;
    try {
      if (latCtrl.text.trim().isNotEmpty) lat = double.parse(latCtrl.text.trim());
      if (lonCtrl.text.trim().isNotEmpty) lon = double.parse(lonCtrl.text.trim());
    } catch (_) {}

    return SupportFileItem(
      file: picked,
      station: stationCtrl.text.trim().isEmpty ? null : stationCtrl.text.trim(),
      caption: captionCtrl.text.trim().isEmpty ? null : captionCtrl.text.trim(),
      lat: lat,
      lon: lon,
    );
  }

  Future<void> _addSupportingDocFlow() async {
    final already = _supportingDocs.map((s) => s.type).toSet();
    final availableEntries = additionalTitles.entries.where((e) => !already.contains(e.key)).toList();

    if (availableEntries.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No more types available'),
          content: const Text('You have already added all supporting document types (A..M). Remove a type if you need to re-add it.'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    String selectedType = availableEntries.first.key;

    final type = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String tmp = selectedType;
        return AlertDialog(
          title: const Text('Select supporting document type'),
          content: StatefulBuilder(builder: (ctx2, setStateDialog) {
            return DropdownButtonFormField<String>(
              value: tmp,
              items: availableEntries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text('${e.key} — ${e.value}')))
                  .toList(),
              onChanged: (v) {
                tmp = v ?? availableEntries.first.key;
                setStateDialog(() {});
              },
            );
          }),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx, tmp);
                },
                child: const Text('Next')),
          ],
        );
      },
    );
    if (type == null) return;

    final labels = additionalRequirements[type] ?? [];
    final Map<String, SupportFileItem?> attachments = {for (var l in labels) l: null};

    final completed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setStateDialog) {
          return AlertDialog(
            scrollable: true,
            title: Text('Attach files for $type — ${additionalTitles[type]}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (labels.isEmpty) const Text('No specific requirements listed for this type.'),
                for (var label in labels) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    subtitle: attachments[label] != null
                        ? Text(
                            '${attachments[label]!.file.name}'
                            '${attachments[label]!.station != null ? '\nStation: ${attachments[label]!.station}' : ''}'
                            '${attachments[label]!.caption != null ? '\nCaption: ${attachments[label]!.caption}' : ''}'
                            '${(attachments[label]!.lat != null && attachments[label]!.lon != null) ? '\nLat: ${attachments[label]!.lat}, Lon: ${attachments[label]!.lon}' : ''}',
                          )
                        : const Text('No file attached'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      TextButton.icon(
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Attach'),
                        onPressed: () async {
                          final item = await _pickFileWithMetadata(label);
                          if (!mounted) return;
                          setStateDialog(() {
                            attachments[label] = item;
                          });
                        },
                      ),
                      if (attachments[label] != null)
                        IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () {
                            setStateDialog(() {
                              attachments[label] = null;
                            });
                          },
                        )
                    ]),
                  ),
                  const SizedBox(height: 6),
                ]
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  final missing = attachments.entries.where((e) => e.value == null).toList();
                  if (missing.isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please attach ${missing.length} required file(s) for Type $type')),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('Add Type'),
              ),
            ],
          );
        });
      },
    );

    if (completed == true) {
      final Map<String, SupportFileItem> finalMap = {};
      attachments.forEach((k, v) {
        if (v != null) finalMap[k] = v;
      });
      setState(() {
        _supportingDocs.add(SupportingDoc(type: type, title: additionalTitles[type] ?? '', filesByLabel: finalMap));
      });
    }
  }

  void _removeSupportingDoc(int idx) {
    setState(() {
      _supportingDocs.removeAt(idx);
    });
  }

  Future<void> _addPlatformFileToRequest(http.MultipartRequest request, String fieldName, PlatformFile pf) async {
    if (kIsWeb) {
      final bytes = pf.bytes;
      if (bytes == null) throw Exception('File bytes missing for web for ${pf.name}');
      request.files.add(http.MultipartFile.fromBytes(fieldName, bytes, filename: pf.name));
    } else {
      // Native platforms: use File path and stream
      final file = File(pf.path!);
      final stream = http.ByteStream(file.openRead());
      final length = await file.length();
      request.files.add(http.MultipartFile(fieldName, stream, length, filename: p.basename(file.path)));
    }
  }

  Future<void> _upload() async {
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) return;

    final isResumption = widget.uploadType.toLowerCase().contains('resumption');
    if (isResumption) {
      if (_reqLetterRequest == null || _reqApprovedSuspension == null || _reqCertifiedContract == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attach all required Resumption documents.')));
        return;
      }
    }

    setState(() {
      _uploading = true;
    });

    try {
      final uri = Uri.parse(_serverUploadUrl);
      final request = http.MultipartRequest('POST', uri);

      // Optional: set header
      request.headers['Accept'] = 'application/json';

      request.fields['type'] = widget.uploadType;
      request.fields['contractorName'] = _contractorController.text;
      request.fields['projectName'] = _projectController.text;
      request.fields['notes'] = _notesController.text;

      // Attach required resumption files under distinct field names
      if (_reqLetterRequest != null) {
        await _addPlatformFileToRequest(request, 'required_letter_request', _reqLetterRequest!);
      }
      if (_reqApprovedSuspension != null) {
        await _addPlatformFileToRequest(request, 'required_approved_suspension', _reqApprovedSuspension!);
      }
      if (_reqCertifiedContract != null) {
        await _addPlatformFileToRequest(request, 'required_certified_contract', _reqCertifiedContract!);
      }

      // Attach supporting docs: each sub-file is attached and we will build metadata
      final List<Map<String, dynamic>> supportMeta = [];

      for (final sd in _supportingDocs) {
        final List<Map<String, dynamic>> items = [];
        for (final entry in sd.filesByLabel.entries) {
          final label = entry.key;
          final item = entry.value;
          final filename = item.file.name;

          // multiple files under the same field name 'supporting_files' (server uses req.files)
          await _addPlatformFileToRequest(request, 'supporting_files', item.file);

          items.add({
            'label': label,
            'filename': filename,
            'station': item.station,
            'caption': item.caption,
            'lat': item.lat,
            'lon': item.lon,
          });
        }
        supportMeta.add({'type': sd.type, 'title': sd.title, 'items': items});
      }

      request.fields['supporting_files_metadata'] = jsonEncode(supportMeta);

      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload successful')));
        setState(() {
          _reqLetterRequest = null;
          _reqApprovedSuspension = null;
          _reqCertifiedContract = null;
          _supportingDocs.clear();
          _contractorController.clear();
          _projectController.clear();
          _notesController.clear();
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: ${resp.statusCode} — ${resp.body}')));
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

  Widget _buildRequiredFileTile(String label, PlatformFile? file, VoidCallback onPick) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: file != null ? Text(file.name) : const Text('No file attached'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        TextButton.icon(onPressed: onPick, icon: const Icon(Icons.attach_file), label: const Text('Attach')),
        if (file != null)
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              setState(() {
                if (label.contains('Letter')) _reqLetterRequest = null;
                if (label.contains('Approved Suspension')) _reqApprovedSuspension = null;
                if (label.contains('Certified True Copy')) _reqCertifiedContract = null;
              });
            },
          )
      ]),
    );
  }

  @override
  void dispose() {
    _contractorController.dispose();
    _projectController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isResumption = widget.uploadType.toLowerCase().contains('resumption');

    return Scaffold(
      appBar: AppBar(title: Text('Upload — ${widget.uploadType}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _contractorController,
              decoration: const InputDecoration(labelText: 'Contractor / Requestor Name'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _projectController,
              decoration: const InputDecoration(labelText: 'Project Name / Contract No.'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'Notes / Reason'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            if (isResumption) ...[
              const Text('Required Documents (to be submitted by the Contractor)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildRequiredFileTile('1. Letter Request of the Contractor for Contract Time Resumption', _reqLetterRequest, () => _pickRequiredFile(1)),
              _buildRequiredFileTile('2. Approved Suspension Order', _reqApprovedSuspension, () => _pickRequiredFile(2)),
              _buildRequiredFileTile('3. Certified True Copy of Original Contract', _reqCertifiedContract, () => _pickRequiredFile(3)),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              const Text('Supporting / Additional Documents (A..M)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ElevatedButton.icon(
                onPressed: _addSupportingDocFlow,
                icon: const Icon(Icons.add),
                label: const Text('Add supporting document (A..M)'),
              ),
              const SizedBox(height: 8),
              if (_supportingDocs.isNotEmpty)
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _supportingDocs.length,
                  itemBuilder: (c, i) {
                    final sd = _supportingDocs[i];
                    return ExpansionTile(
                      leading: CircleAvatar(child: Text(sd.type)),
                      title: Text('${sd.type} — ${sd.title}'),
                      subtitle: Text('${sd.filesByLabel.length} file(s) attached'),
                      children: [
                        for (final entry in sd.filesByLabel.entries)
                          ListTile(
                            title: Text(entry.key, style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                              '${entry.value.file.name}'
                              '${entry.value.station != null ? '\nStation: ${entry.value.station}' : ''}'
                              '${entry.value.caption != null ? '\nCaption: ${entry.value.caption}' : ''}'
                              '${(entry.value.lat != null && entry.value.lon != null) ? '\nLat: ${entry.value.lat}, Lon: ${entry.value.lon}' : ''}',
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(onPressed: () => _removeSupportingDoc(i), icon: const Icon(Icons.delete), label: Text('Remove Type ${sd.type}')),
                          ],
                        )
                      ],
                    );
                  },
                )
              else
                const Text('No supporting documents added.'),
            ] else ...[
              ElevatedButton.icon(
                onPressed: () async {
                  final f = await _pickSingleFile();
                  if (f == null) return;
                  setState(() {
                    final item = SupportFileItem(file: f);
                    _supportingDocs.add(SupportingDoc(type: 'X', title: 'Attached file', filesByLabel: {'Attached file': item}));
                  });
                },
                icon: const Icon(Icons.attach_file),
                label: const Text('Attach files'),
              ),
              const SizedBox(height: 8),
              if (_supportingDocs.isNotEmpty)
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _supportingDocs.length,
                  itemBuilder: (c, i) {
                    final sd = _supportingDocs[i];
                    return ListTile(
                      leading: const Icon(Icons.insert_drive_file),
                      title: Text('${sd.type} — ${sd.title}'),
                      subtitle: Text(sd.filesByLabel.values.first.file.name),
                      trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () => _removeSupportingDoc(i)),
                    );
                  },
                )
            ],
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _uploading ? null : _upload,
              icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload),
              label: Text(_uploading ? 'Uploading...' : 'Upload'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Notes:\n• Required documents must be attached for Resumption.\n• For geotagged pictures you can auto-fill station coordinates using your device location (permission required).',
              style: TextStyle(fontSize: 12),
            ),
          ]),
        ),
      ),
    );
  }
}
