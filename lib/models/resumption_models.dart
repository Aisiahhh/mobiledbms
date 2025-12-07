// lib/models/resumption_models.dart
import 'package:file_picker/file_picker.dart';

/// Defensive model for resumption upload (server uses UUID strings for id)
class ResumptionUpload {
  final String id;
  final String uploadType;
  final String contractorName;
  final String projectName;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  ResumptionUpload({
    required this.id,
    required this.uploadType,
    required this.contractorName,
    required this.projectName,
    this.notes,
    required this.createdAt,
    this.updatedAt,
  });

  factory ResumptionUpload.fromJson(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);

    // id: server returns UUID string, keep as string
    final id = (map['id'] ?? '').toString();

    // upload_type
    final uploadType = (map['upload_type'] ?? map['type'] ?? '').toString();

    final contractorName = (map['contractor_name'] ?? map['contractorName'] ?? '').toString();
    final projectName = (map['project_name'] ?? map['projectName'] ?? '').toString();
    final notes = map['notes']?.toString();

    // createdAt / updatedAt: handle ISO strings or epoch numbers (seconds or millis)
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      if (v is String) {
        return DateTime.tryParse(v) ?? DateTime.now();
      }
      if (v is int) {
        // heuristics: if <= 1e10 treat as seconds, else millis
        if (v <= 9999999999) {
          return DateTime.fromMillisecondsSinceEpoch(v * 1000);
        } else {
          return DateTime.fromMillisecondsSinceEpoch(v);
        }
      }
      if (v is double) {
        final iv = v.toInt();
        if (iv <= 9999999999) {
          return DateTime.fromMillisecondsSinceEpoch(iv * 1000);
        } else {
          return DateTime.fromMillisecondsSinceEpoch(iv);
        }
      }
      return DateTime.now();
    }

    final createdAt = parseDate(map['created_at'] ?? map['createdAt'] ?? map['created']);
    final updatedAtVal = map['updated_at'] ?? map['updatedAt'];
    final updatedAt = updatedAtVal != null ? parseDate(updatedAtVal) : null;

    return ResumptionUpload(
      id: id,
      uploadType: uploadType,
      contractorName: contractorName,
      projectName: projectName,
      notes: notes,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'upload_type': uploadType,
      'contractor_name': contractorName,
      'project_name': projectName,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

/// Supporting file record - IDs are strings (server may use UUID or numeric, keep string to be safe)
class SupportingFile {
  final String id;
  final String uploadId;
  final String docType;
  final String? docTitle;
  final String? label;
  final String filename;
  final String storagePath;
  final String? station;
  final String? caption;
  final double? latitude;
  final double? longitude;
  final String? signedUrl;
  final DateTime createdAt;

  SupportingFile({
    required this.id,
    required this.uploadId,
    required this.docType,
    this.docTitle,
    this.label,
    required this.filename,
    required this.storagePath,
    this.station,
    this.caption,
    this.latitude,
    this.longitude,
    this.signedUrl,
    required this.createdAt,
  });

  factory SupportingFile.fromJson(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);

    String parseId(dynamic v) => v == null ? '' : v.toString();

    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      if (v is int) {
        if (v <= 9999999999) return DateTime.fromMillisecondsSinceEpoch(v * 1000);
        return DateTime.fromMillisecondsSinceEpoch(v);
      }
      if (v is double) {
        final iv = v.toInt();
        if (iv <= 9999999999) return DateTime.fromMillisecondsSinceEpoch(iv * 1000);
        return DateTime.fromMillisecondsSinceEpoch(iv);
      }
      return DateTime.now();
    }

    double? parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return SupportingFile(
      id: parseId(map['id']),
      uploadId: parseId(map['upload_id'] ?? map['uploadId']),
      docType: (map['doc_type'] ?? '').toString(),
      docTitle: map['doc_title']?.toString(),
      label: map['label']?.toString(),
      filename: (map['filename'] ?? '').toString(),
      storagePath: (map['storage_path'] ?? '').toString(),
      station: map['station']?.toString(),
      caption: map['caption']?.toString(),
      latitude: parseDouble(map['latitude']),
      longitude: parseDouble(map['longitude']),
      signedUrl: map['signedUrl']?.toString() ?? map['signed_url']?.toString(),
      createdAt: parseDate(map['created_at'] ?? map['createdAt']),
    );
  }
}

/// Response for listing uploads — parse ints defensively
class UploadListResponse {
  final bool ok;
  final List<ResumptionUpload> uploads;
  final int total;
  final int page;
  final int limit;

  UploadListResponse({
    required this.ok,
    required this.uploads,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory UploadListResponse.fromJson(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);
    final rawUploads = map['uploads'];
    final uploadsList = <ResumptionUpload>[];

    if (rawUploads is List) {
      for (final item in rawUploads) {
        if (item is Map<String, dynamic>) {
          uploadsList.add(ResumptionUpload.fromJson(item));
        } else if (item is Map) {
          uploadsList.add(ResumptionUpload.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    int parseIntSafe(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is double) return v.toInt();
      return int.tryParse(v.toString()) ?? 0;
    }

    return UploadListResponse(
      ok: map['ok'] == true,
      uploads: uploadsList,
      total: parseIntSafe(map['total']),
      page: parseIntSafe(map['page']),
      limit: parseIntSafe(map['limit']),
    );
  }
}

/// Upload detail response
class UploadDetailResponse {
  final bool ok;
  final ResumptionUpload upload;
  final List<SupportingFile> files;

  UploadDetailResponse({
    required this.ok,
    required this.upload,
    required this.files,
  });

  factory UploadDetailResponse.fromJson(Map<String, dynamic> json) {
    final map = Map<String, dynamic>.from(json);

    final uploadMap = (map['upload'] as Map?) ?? {};
    final filesRaw = map['files'] as List? ?? [];

    final files = filesRaw.map<SupportingFile>((e) {
      if (e is Map<String, dynamic>) return SupportingFile.fromJson(e);
      return SupportingFile.fromJson(Map<String, dynamic>.from(e as Map));
    }).toList();

    return UploadDetailResponse(
      ok: map['ok'] == true,
      upload: ResumptionUpload.fromJson(Map<String, dynamic>.from(uploadMap)),
      files: files,
    );
  }
}

/// Human-friendly titles and additional requirements (unchanged)
final Map<String, String> additionalTitles = {
  'A': 'Due to Rainy/Unworkable Days considered unfavorable for prosecution of the works at the site',
  'B': 'Due to Delay in payment of Contractor\'s Claim for Progress Billing/s',
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

final Map<String, List<String>> additionalRequirements = {
  'A': ['Geotagged pictures (with caption) showing that the site is workable'],
  'B': ['Certified copy of Vouchers/Progress Billings', 'Certification from the Accounting Division of payments received'],
  'C': ['Geotagged pictures before and after RROW problem resolved', 'Certification from the Barangay Captain/Mayor that RROW Problem was resolved'],
  'D': ['Certification from PNP station commander and confirmation by the DILG Regional Director'],
  'E': ['Geotagged pictures showing resolution of inaccessibility', 'Relevant document proving inaccessibility was resolved'],
  'F': ['Geotagged pictures showing obstruction removed', 'Relevant documents (permit, communication letters, minutes of meeting)'],
  'G': ['Proof of date of approval of construction plan/drawings'],
  'H': ['Certification from DTI and suppliers that materials are available'],
  'I': ['Pictures showing effect of force majeure addressed for Resumption Order', 'Relevant documents (communication letters, minutes of meeting)'],
  'J': ['Contractor request duly received by the Implementing Office for Resumption', 'Copy of the MMDA Permit/Clearance for Road Repair/Excavation/Traffic Clearance'],
  'K': ['Contractor request duly received by the Implementing Office for Resumption', 'Copy of the LGU Permit/Clearance/Re-blocking permit/clearance'],
  'L': ['Contractor request duly received by the Implementing Office for Resumption', 'Copy of DENR Clearance/Permit to cut/remove trees', 'PCA Clearance (for Coconut)'],
  'M': ['Contractor request to the Implementing Office for Resumption', 'Certified true copy of Bill of Lading', 'Original copy of Custom Clearance', 'Certification from the Implementing Office that delayed delivery was resolved'],
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
