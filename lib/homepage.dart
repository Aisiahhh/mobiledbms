import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_dbms/pert_upload_page.dart';    // keep if you have this
import 'package:mobile_dbms/time_variance/resumption/resumption.dart';
import 'package:mobile_dbms/time_variance/resumption/resumption_list_page.dart';
import 'package:mobile_dbms/variation_order.dart';    // keep if you have this

class _Option {
  final String title;
  final IconData icon;
  const _Option(this.title, this.icon);
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  final List<_Option> _mainOptions = const [
    _Option('TIME Variance', Icons.access_time),
    _Option('VARIATION ORDER', Icons.edit_note),
    _Option('PERT / PDM', Icons.timeline),
  ];

  static const List<String> _timeVarianceSub = [
    'Work Suspension Order',
    'Work Resumption Order',
    'Contract Time Extension',
  ];

  static const List<String> _pertSub = [
    'Original',
    'Revised',
  ];

  Future<void> _openTimeVariance(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('Select TIME Variance type'),
          children: _timeVarianceSub
              .map((s) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, s),
                    child: Text(s),
                  ))
              .toList(),
        );
      },
    );

    if (choice != null) {
      // For Work Resumption Order, navigate to the list page
      if (choice == 'Work Resumption Order') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResumptionListPage(
              serverUrl: kIsWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000', uploadType: '',
            ),
          ),
        );
      } else {
        // For other TIME Variance types, use the existing upload page
        // Note: You'll need to update your UploadPage to take serverUrl parameter
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UploadPage(
              uploadType: 'TIME Variance — $choice',
              serverUrl: kIsWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000',
            ),
          ),
        );
      }
    }
  }

  Future<void> _openPertPdm(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('Select PERT / PDM version'),
          children: _pertSub
              .map((s) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, s),
                    child: Text(s),
                  ))
              .toList(),
        );
      },
    );

    if (choice != null) {
      // If your PertUploadPage supports an initial mode, pass it. Otherwise call without params.
      try {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PertUploadPage(
              initialMode: choice == 'Original' ? PertMode.original : PertMode.revised,
            ),
          ),
        );
      } catch (_) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PertUploadPage(),
          ),
        );
      }
    }
  }

  void _onOptionTap(BuildContext context, _Option option) {
    final key = option.title.trim().toLowerCase();
    if (key == 'time variance') {
      _openTimeVariance(context);
    } else if (key == 'pert / pdm') {
      _openPertPdm(context);
    } else {
      // Variation Order: direct (adjust widget name if needed)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const VariationUploadPage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Documents')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: GridView.builder(
          itemCount: _mainOptions.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.05,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, idx) {
            final opt = _mainOptions[idx];
            return GestureDetector(
              onTap: () => _onOptionTap(context, opt),
              child: Card(
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(opt.icon, size: 48),
                      const SizedBox(height: 8),
                      Text(
                        opt.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (opt.title == 'TIME Variance' || opt.title == 'PERT / PDM')
                        const Text(
                          '(tap to choose)',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}