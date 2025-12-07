// lib/time_variance.dart
import 'package:flutter/material.dart';
import 'package:mobile_dbms/time_variance/resumption/resumption.dart';

class TimeVariancePage extends StatelessWidget {
  final String subtype; // e.g. "Work Resumption Order"
  const TimeVariancePage({super.key, required this.subtype});

  @override
  Widget build(BuildContext context) {
    // Reuse UploadPage but give a clearer name / route
    return UploadPage(uploadType: 'TIME Variance — $subtype', serverUrl: '',);
  }
}
