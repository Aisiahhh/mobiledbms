// lib/variation_upload_page.dart
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class VariationUploadPage extends StatefulWidget {
  const VariationUploadPage({super.key});

  @override
  State<VariationUploadPage> createState() => _VariationUploadPageState();
}

class _VariationUploadPageState extends State<VariationUploadPage> {
  final _formKey = GlobalKey<FormState>();

  // metadata
  final TextEditingController _contractorController = TextEditingController();
  final TextEditingController _projectController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  // flags
  bool _withAdditionalCost = false; // triggers Performance Security
  bool _substitutionInvolved = false; // triggers 8.1-8.4
  bool _includesPilingWorks = false; // triggers borehole/piling data
  bool _proposedTimeExtension = false; // triggers schedule + derivation

  // files (I. To be submitted by Contractor/Consultant)
  PlatformFile? _contractorRequest; // 1
  PlatformFile? _performanceSecurity; // 2 (conditional)
  PlatformFile? _dulySignedApprovedPlans; // 3
  PlatformFile? _designAnalysisComputations; // 4 (if applicable)
  PlatformFile? _approvedPlansSet; // 5 (Complete set: As-staked, Original, Revised and As-built)
  PlatformFile? _approvedContractAndClauses; // 6
  PlatformFile? _detailedQuantityCalculations; // 7

  // substitution files 8.1 - 8.4 (conditional)
  PlatformFile? _certNonAvailability3Suppliers; // 8.1
  PlatformFile? _techSpecsOriginalAndSubstitute; // 8.2
  PlatformFile? _designComputationsForSubstitute; // 8.3
  PlatformFile? _costEstimateSubstitute; // 8.4

  PlatformFile? _boreholePilingData; // 9 (conditional)
  PlatformFile? _straightLineDiagram; // 10
  PlatformFile? _latestApprovedConstructionSchedule; // 11 (conditional/time extension)
  PlatformFile? _derivationOfTimeExtension; // 12 (conditional)
  // DUPA (13)
  PlatformFile? _dupaDetailedEstimate; // 13.1
  PlatformFile? _dupaCanvassPrice; // 13.2
  PlatformFile? _constructionMethodology; // 13.3
  PlatformFile? _copyPreviouslyApprovedTimeExtension; // 14 (if any)
  PlatformFile? _conformityPerformanceBond; // 15 (if extension of contract time)
  PlatformFile? _certifiedTrueCopySetOfVOs; // 16 (one set certified true copy)

  bool _uploading = false;

  // Set this to the server upload endpoint your Node server exposes (reachable from device/emulator)
  final String _serverUploadUrl = kIsWeb ? 'http://localhost:3000/upload' : 'http://10.0.2.2:3000/upload';

  Future<PlatformFile?> _pickSingleFile() async {
    final r = await FilePicker.platform.pickFiles(withData: true);
    if (r == null) return null;
    return r.files.first;
  }

  Future<void> _attachFileToSetter(Future<PlatformFile?> Function() picker, void Function(PlatformFile?) setter) async {
    final f = await picker();
    if (f == null) return;
    setState(() => setter(f));
  }

  // helper to attach PlatformFile to MultipartRequest cross-platform
  Future<void> _addPlatformFileToRequest(http.MultipartRequest req, String fieldName, PlatformFile pf) async {
    if (kIsWeb) {
      final bytes = pf.bytes;
      if (bytes == null) throw Exception('Missing file bytes for ${pf.name} on web');
      req.files.add(http.MultipartFile.fromBytes(fieldName, bytes, filename: pf.name));
    } else {
      final file = File(pf.path!);
      final stream = http.ByteStream(file.openRead());
      final length = await file.length();
      req.files.add(http.MultipartFile(fieldName, stream, length, filename: p.basename(file.path)));
    }
  }

  // validate required attachments before upload
  List<String> _validateRequiredFiles() {
    final missing = <String>[];
    if (_contractorRequest == null) missing.add('Contractor’s Request (I.1)');
    if (_dulySignedApprovedPlans == null) missing.add('Duly signed/approved plans (I.3)');
    if (_approvedPlansSet == null) missing.add('Complete set of approved plans (I.5)');
    if (_approvedContractAndClauses == null) missing.add('Copy of approved contract and clauses (I.6)');
    if (_detailedQuantityCalculations == null) missing.add('Detailed Quantity Calculations (I.7)');
    if (_straightLineDiagram == null) missing.add('Straight-line Diagram (I.10)');
    if (_dupaDetailedEstimate == null) missing.add('DUPA — Detailed Estimate (13.1)');
    if (_dupaCanvassPrice == null) missing.add('DUPA — Canvass Price / Materials Cost (13.2)');
    if (_constructionMethodology == null) missing.add('DUPA — Construction Methodology (13.3)');
    if (_certifiedTrueCopySetOfVOs == null) missing.add('Certified true copy set of all approved Variation Orders (I.16)');

    if (_withAdditionalCost && _performanceSecurity == null) missing.add('Performance Security (I.2)');

    if (_substitutionInvolved) {
      if (_certNonAvailability3Suppliers == null) missing.add('Certification on non-availability by 3 suppliers (8.1)');
      if (_techSpecsOriginalAndSubstitute == null) missing.add('Technical specifications of original and substitute materials (8.2)');
      if (_designComputationsForSubstitute == null) missing.add('Design computations for substitute material (8.3)');
      if (_costEstimateSubstitute == null) missing.add('Cost Estimate for substitute (8.4)');
    }

    if (_includesPilingWorks && _boreholePilingData == null) missing.add('Copy of borehole/piling data (I.9)');

    if (_proposedTimeExtension) {
      if (_latestApprovedConstructionSchedule == null) missing.add('Latest approved construction schedule (I.11)');
      if (_derivationOfTimeExtension == null) missing.add('Derivation of Time Extension (I.12)');
    }

    // copy of previously approved time extension (14) is optional but recommend to attach if present
    return missing;
  }

  Future<void> _upload() async {
    if (_formKey.currentState == null) return;
    if (!_formKey.currentState!.validate()) return;

    final missing = _validateRequiredFiles();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please attach: ${missing.join(', ')}')));
      return;
    }

    setState(() => _uploading = true);

    try {
      final uri = Uri.parse(_serverUploadUrl);
      final request = http.MultipartRequest('POST', uri);
      request.headers['Accept'] = 'application/json';

      // metadata fields
      request.fields['type'] = 'VARIATION ORDER'; // server-side grouping
      request.fields['contractorName'] = _contractorController.text.trim();
      request.fields['projectName'] = _projectController.text.trim();
      request.fields['notes'] = _notesController.text.trim();

      // flags
      request.fields['variation_with_additional_cost'] = _withAdditionalCost ? '1' : '0';
      request.fields['variation_substitution_involved'] = _substitutionInvolved ? '1' : '0';
      request.fields['variation_includes_piling'] = _includesPilingWorks ? '1' : '0';
      request.fields['variation_proposed_time_extension'] = _proposedTimeExtension ? '1' : '0';

      // attach files with clear field names
      // I.1 Contractor's Request
      if (_contractorRequest != null) {
        await _addPlatformFileToRequest(request, 'variation_contractor_request', _contractorRequest!);
      }
      // I.2 Performance Security (if with additional cost)
      if (_performanceSecurity != null) {
        await _addPlatformFileToRequest(request, 'variation_performance_security', _performanceSecurity!);
      }
      // I.3 Duly signed/approved plans for proposed design changes
      if (_dulySignedApprovedPlans != null) {
        await _addPlatformFileToRequest(request, 'variation_signed_approved_plans', _dulySignedApprovedPlans!);
      }
      // I.4 Design Analysis & Computations
      if (_designAnalysisComputations != null) {
        await _addPlatformFileToRequest(request, 'variation_design_analysis_computations', _designAnalysisComputations!);
      }
      // I.5 Complete set of approved plans
      if (_approvedPlansSet != null) {
        await _addPlatformFileToRequest(request, 'variation_approved_plans_set', _approvedPlansSet!);
      }
      // I.6 Copy of approved contract incl GCC/COPA/SCC and previous VOs
      if (_approvedContractAndClauses != null) {
        await _addPlatformFileToRequest(request, 'variation_approved_contract_clauses', _approvedContractAndClauses!);
      }
      // I.7 Detailed Quantity Calculations
      if (_detailedQuantityCalculations != null) {
        await _addPlatformFileToRequest(request, 'variation_detailed_quantity_calculations', _detailedQuantityCalculations!);
      }

      // 8 substitution group (conditional)
      if (_substitutionInvolved) {
        if (_certNonAvailability3Suppliers != null) {
          await _addPlatformFileToRequest(request, 'variation_sub_8_1_nonavail_cert', _certNonAvailability3Suppliers!);
        }
        if (_techSpecsOriginalAndSubstitute != null) {
          await _addPlatformFileToRequest(request, 'variation_sub_8_2_tech_specs', _techSpecsOriginalAndSubstitute!);
        }
        if (_designComputationsForSubstitute != null) {
          await _addPlatformFileToRequest(request, 'variation_sub_8_3_design_computations', _designComputationsForSubstitute!);
        }
        if (_costEstimateSubstitute != null) {
          await _addPlatformFileToRequest(request, 'variation_sub_8_4_cost_estimate', _costEstimateSubstitute!);
        }
      }

      // I.9 borehole/piling data (conditional)
      if (_boreholePilingData != null) {
        await _addPlatformFileToRequest(request, 'variation_borehole_piling_data', _boreholePilingData!);
      }
      // I.10 straight-line diagram
      if (_straightLineDiagram != null) {
        await _addPlatformFileToRequest(request, 'variation_straight_line_diagram', _straightLineDiagram!);
      }
      // I.11 latest approved construction schedule (if proposed time extension)
      if (_latestApprovedConstructionSchedule != null) {
        await _addPlatformFileToRequest(request, 'variation_latest_approved_schedule', _latestApprovedConstructionSchedule!);
      }
      // I.12 derivation of time extension
      if (_derivationOfTimeExtension != null) {
        await _addPlatformFileToRequest(request, 'variation_derivation_time_extension', _derivationOfTimeExtension!);
      }

      // 13 DUPA subitems
      if (_dupaDetailedEstimate != null) {
        await _addPlatformFileToRequest(request, 'variation_dupa_detailed_estimate', _dupaDetailedEstimate!);
      }
      if (_dupaCanvassPrice != null) {
        await _addPlatformFileToRequest(request, 'variation_dupa_canvass_price', _dupaCanvassPrice!);
      }
      if (_constructionMethodology != null) {
        await _addPlatformFileToRequest(request, 'variation_dupa_construction_methodology', _constructionMethodology!);
      }

      // 14 copy of previously approved time extension (optional)
      if (_copyPreviouslyApprovedTimeExtension != null) {
        await _addPlatformFileToRequest(request, 'variation_previous_approved_time_extension', _copyPreviouslyApprovedTimeExtension!);
      }

      // 15 conformity of contractor's performance bond (if applicable)
      if (_conformityPerformanceBond != null) {
        await _addPlatformFileToRequest(request, 'variation_conformity_performance_bond', _conformityPerformanceBond!);
      }

      // 16 one set certified true copy of all approved VOs
      if (_certifiedTrueCopySetOfVOs != null) {
        await _addPlatformFileToRequest(request, 'variation_certified_true_copy_set', _certifiedTrueCopySetOfVOs!);
      }

      // Build metadata JSON summarizing attached items and flags
      final meta = {
        'with_additional_cost': _withAdditionalCost,
        'substitution_involved': _substitutionInvolved,
        'includes_piling_works': _includesPilingWorks,
        'proposed_time_extension': _proposedTimeExtension,
        'files': <Map<String, String>>[], // Ensure 'files' is initialized as a list
      };

      void addFileMeta(String label, PlatformFile? pf) {
        if (pf != null) {
          (meta['files'] as List).add({'label': label, 'filename': pf.name});
        }
      }

      addFileMeta('Contractor Request (I.1)', _contractorRequest);
      addFileMeta('Performance Security (I.2)', _performanceSecurity);
      addFileMeta('Signed/Approved Plans (I.3)', _dulySignedApprovedPlans);
      addFileMeta('Design Analysis (I.4)', _designAnalysisComputations);
      addFileMeta('Approved Plans Set (I.5)', _approvedPlansSet);
      addFileMeta('Approved Contract & Clauses (I.6)', _approvedContractAndClauses);
      addFileMeta('Detailed Quantity Calculations (I.7)', _detailedQuantityCalculations);
      addFileMeta('Sub: non-availability 3 suppliers (8.1)', _certNonAvailability3Suppliers);
      addFileMeta('Sub: tech specs (8.2)', _techSpecsOriginalAndSubstitute);
      addFileMeta('Sub: design computations (8.3)', _designComputationsForSubstitute);
      addFileMeta('Sub: cost estimate (8.4)', _costEstimateSubstitute);
      addFileMeta('Borehole/Piling data (I.9)', _boreholePilingData);
      addFileMeta('Straight-line Diagram (I.10)', _straightLineDiagram);
      addFileMeta('Latest Approved Schedule (I.11)', _latestApprovedConstructionSchedule);
      addFileMeta('Derivation of Time Extension (I.12)', _derivationOfTimeExtension);
      addFileMeta('DUPA Detailed Estimate (13.1)', _dupaDetailedEstimate);
      addFileMeta('DUPA Canvass Price (13.2)', _dupaCanvassPrice);
      addFileMeta('Construction Methodology (13.3)', _constructionMethodology);
      addFileMeta('Copy prev approved Time Extension (14)', _copyPreviouslyApprovedTimeExtension);
      addFileMeta('Conformity Performance Bond (15)', _conformityPerformanceBond);
      addFileMeta('Certified true copy set of VOs (16)', _certifiedTrueCopySetOfVOs);

      request.fields['variation_metadata'] = jsonEncode(meta);

      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload successful')));
        _clearForm();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: ${resp.statusCode} — ${resp.body}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _uploading = false);
    }
  }

  void _clearForm() {
    setState(() {
      _contractorController.clear();
      _projectController.clear();
      _notesController.clear();
      _withAdditionalCost = false;
      _substitutionInvolved = false;
      _includesPilingWorks = false;
      _proposedTimeExtension = false;

      _contractorRequest = null;
      _performanceSecurity = null;
      _dulySignedApprovedPlans = null;
      _designAnalysisComputations = null;
      _approvedPlansSet = null;
      _approvedContractAndClauses = null;
      _detailedQuantityCalculations = null;
      _certNonAvailability3Suppliers = null;
      _techSpecsOriginalAndSubstitute = null;
      _designComputationsForSubstitute = null;
      _costEstimateSubstitute = null;
      _boreholePilingData = null;
      _straightLineDiagram = null;
      _latestApprovedConstructionSchedule = null;
      _derivationOfTimeExtension = null;
      _dupaDetailedEstimate = null;
      _dupaCanvassPrice = null;
      _constructionMethodology = null;
      _copyPreviouslyApprovedTimeExtension = null;
      _conformityPerformanceBond = null;
      _certifiedTrueCopySetOfVOs = null;
    });
  }

  @override
  void dispose() {
    _contractorController.dispose();
    _projectController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Widget _fileCard(String label, PlatformFile? file, VoidCallback onAttach, {String? hint}) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(label),
        subtitle: file != null ? Text(file.name) : Text(hint ?? 'No file attached'),
        trailing: Wrap(spacing: 8, children: [
          TextButton.icon(onPressed: onAttach, icon: const Icon(Icons.attach_file), label: const Text('Attach')),
          if (file != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => setState(() {
                // caller should set the right field to null
                // but we leave specific handlers in-place (see usage below)
              }),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Variation Order — Submission (Contractor)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _contractorController,
              decoration: const InputDecoration(labelText: 'Contractor / Consultant Name'),
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
              decoration: const InputDecoration(labelText: 'Notes / Short description (optional)'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            const Text('Attach required documents (I. To be submitted by the Contractor/Consultant)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            // I.1 Contractor's Request
            _fileCard('1. Contractor\'s Request', _contractorRequest, () async {
              final f = await _pickSingleFile();
              if (f == null) return;
              setState(() => _contractorRequest = f);
            }),

            // I.2 Performance Security (conditional)
            CheckboxListTile(
              value: _withAdditionalCost,
              onChanged: (v) => setState(() => _withAdditionalCost = v ?? false),
              title: const Text('With additional cost? (If yes, attach Performance Security)'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_withAdditionalCost)
              _fileCard('2. Performance Security (verified copy)', _performanceSecurity, () async {
                final f = await _pickSingleFile();
                if (f == null) return;
                setState(() => _performanceSecurity = f);
              }),

            // I.3 Duly signed/approved plans for proposed design changes
            _fileCard('3. Duly signed / approved plans for proposed design changes', _dulySignedApprovedPlans, () async {
              final f = await _pickSingleFile();
              if (f == null) return;
              setState(() => _dulySignedApprovedPlans = f);
            }),

            // I.4 Design Analysis & Computations (if applicable)
            _fileCard('4. Design Analysis & Computations (if applicable)', _designAnalysisComputations, () async {
              final f = await _pickSingleFile();
              if (f == null) return;
              setState(() => _designAnalysisComputations = f);
            }),

            // I.5 Complete set of the approved plans (As-staked, Original, Revised, As-built)
            _fileCard('5. Complete set of approved plans (As-staked / Original / Revised / As-built)', _approvedPlansSet, () async {
              final f = await _pickSingleFile();
              if (f == null) return;
              setState(() => _approvedPlansSet = f);
            }),

            // I.6 Copy of approved contract incl GCC / COPA / SCC and previously approved VOs
            _fileCard('6. Copy of Approved Contract (GCC/COPA/SCC) & previous VOs', _approvedContractAndClauses, () async {
              final f = await _pickSingleFile();
              if (f == null) return;
              setState(() => _approvedContractAndClauses = f);
            }),

            // I.7 Detailed Quantity Calculations
            _fileCard('7. Detailed Quantity Calculations', _detailedQuantityCalculations, () async {
              final f = await _pickSingleFile();
              if (f == null) return;
              setState(() => _detailedQuantityCalculations = f);
            }),

            // 8 substitution of materials
            CheckboxListTile(
              value: _substitutionInvolved,
              onChanged: (v) => setState(() => _substitutionInvolved = v ?? false),
              title: const Text('Substitution of original specified materials involved?'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_substitutionInvolved) ...[
              _fileCard('8.1 Certification on non-availability of specified materials by 3 suppliers', _certNonAvailability3Suppliers, () async {
                final f = await _pickSingleFile();
                if (f == null) return;
                setState(() => _certNonAvailability3Suppliers = f);
              }),
              _fileCard('8.2 Technical specifications of original and substitute materials', _techSpecsOriginalAndSubstitute, () async {
                final f = await _pickSingleFile();
                if (f == null) return;
                setState(() => _techSpecsOriginalAndSubstitute = f);
              }),
              _fileCard('8.3 Design computations for the substitute material', _designComputationsForSubstitute, () async {
                final f = await _pickSingleFile();
                if (f == null) return;
                setState(() => _designComputationsForSubstitute = f);
              }),
              _fileCard('8.4 Cost Estimate for substitute', _costEstimateSubstitute, () async {
                final f = await _pickSingleFile();
                if (f == null) return;
                setState(() => _costEstimateSubstitute = f);
              }),
            ],

            // I.9 Borehole/piling data (conditional)
            CheckboxListTile(
              value: _includesPilingWorks,
              onChanged: (v) => setState(() => _includesPilingWorks = v ?? false),
              title: const Text('Includes piling works? (If yes, attach borehole/piling data)'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_includesPilingWorks)
              _fileCard('9. Copy of borehole / piling data (original & actual)', _boreholePilingData, () async {
                final f = await _pickSingleFile();
                if (f == null) return;
                setState(() => _boreholePilingData = f);
              }),

            // I.10 Straight-line diagram
            _fileCard('10. Straight-line Diagram showing proposed works', _straightLineDiagram, () async {
              final f = await _pickSingleFile();
              if (f == null) return;
              setState(() => _straightLineDiagram = f);
            }),

            // I.11 + I.12 time extension
            CheckboxListTile(
              value: _proposedTimeExtension,
              onChanged: (v) => setState(() => _proposedTimeExtension = v ?? false),
              title: const Text('Is there a proposed Time Extension for this V.O.?'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_proposedTimeExtension) ...[
              _fileCard('11. Copy of Latest Approved Construction Schedule', _latestApprovedConstructionSchedule, () async {
                final f = await _pickSingleFile();
                if (f == null) return;
                setState(() => _latestApprovedConstructionSchedule = f);
              }),
              _fileCard('12. Derivation of Time Extension for the proposed V.O.', _derivationOfTimeExtension, () async {
                final f = await _pickSingleFile();
                if (f == null) return;
                setState(() => _derivationOfTimeExtension = f);
              }),
            ],

            const SizedBox(height: 6),
            const Divider(),
            const SizedBox(height: 6),
            const Text('13. Detailed Unit Price Analysis (DUPA) for new items of work (attach below)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _fileCard('13.1 Detailed Estimate of items of work (DUPA)', _dupaDetailedEstimate, () async {
              final f = await _pickSingleFile();
              if (f == null) return;
              setState(() => _dupaDetailedEstimate = f);
            }),
            _fileCard('13.2 Canvass Price / Derivation of Materials Cost delivered at site', _dupaCanvassPrice, () async {
              final f = await _pickSingleFile();
              if (f == null) return;
              setState(() => _dupaCanvassPrice = f);
            }),
            _fileCard('13.3 Construction Methodology (for technical/unusual items)', _constructionMethodology, () async {
              final f = await _pickSingleFile();
              if (f == null) return;
              setState(() => _constructionMethodology = f);
            }),

            // 14 previously approved time extension (optional but attach if any)
            _fileCard('14. Copy of previously approved Time Extension (if any)', _copyPreviouslyApprovedTimeExtension, () async {
              final f = await _pickSingleFile();
              if (f == null) return;
              setState(() => _copyPreviouslyApprovedTimeExtension = f);
            }),

            // 15 Conformity of Contractor's Performance Bond (if there is extension of contract time)
            _fileCard('15. Conformity of Contractor\'s Performance Bond (if time extension)', _conformityPerformanceBond, () async {
              final f = await _pickSingleFile();
              if (f == null) return;
              setState(() => _conformityPerformanceBond = f);
            }),

            // 16 One set certified true copy of all approved Variation Orders
            _fileCard('16. One set certified true copy of approved Variation Orders (for accounting)', _certifiedTrueCopySetOfVOs, () async {
              final f = await _pickSingleFile();
              if (f == null) return;
              setState(() => _certifiedTrueCopySetOfVOs = f);
            }),

            const SizedBox(height: 12),
            // Certification block (contractor)
            const Text('Certification (Contractor) — please fill in', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Print Name (Contractor)'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(labelText: 'Designation'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              onPressed: _uploading ? null : _upload,
              icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cloud_upload),
              label: Text(_uploading ? 'Uploading...' : 'Submit Variation Order'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Notes:\n• Required items are checked from the Variation Order checklist (Annex K). Attach all required files for a faster review.\n• Performance Security is required when additional cost applies (see checklist thresholds).',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 28),
          ]),
        ),
      ),
    );
  }
}
