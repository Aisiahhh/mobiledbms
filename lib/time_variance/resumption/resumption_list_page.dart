import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_dbms/models/resumption_models.dart';
import 'package:mobile_dbms/time_variance/resumption/resumption.dart';
import 'resumption_detail_page.dart';

class ResumptionListPage extends StatefulWidget {
  final String serverUrl;
  final String uploadType;

  const ResumptionListPage({
    super.key,
    required this.serverUrl,
    required this.uploadType,
  });

  @override
  State<ResumptionListPage> createState() => _ResumptionListPageState();
}

class _ResumptionListPageState extends State<ResumptionListPage> {
  List<ResumptionUpload> _uploads = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  int _currentPage = 1;
  final int _limit = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _fetchUploads();
  }

  Future<void> _fetchUploads({bool loadMore = false}) async {
    if (!loadMore) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final uri = Uri.parse('${widget.serverUrl}/resumption/list')
          .replace(queryParameters: {
        'page': _currentPage.toString(),
        'limit': _limit.toString(),
        'type': 'resumption', // This will match "Work Resumption Order"
      });

      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final responseObj = UploadListResponse.fromJson(data);
        
        setState(() {
          if (loadMore) {
            _uploads.addAll(responseObj.uploads);
          } else {
            _uploads = responseObj.uploads;
          }
          _hasMore = responseObj.uploads.length == _limit;
          _hasError = false;
        });
      } else {
        throw Exception('Failed to load uploads: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _refreshUploads() async {
    setState(() {
      _currentPage = 1;
    });
    await _fetchUploads();
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    
    setState(() {
      _currentPage++;
    });
    
    await _fetchUploads(loadMore: true);
  }

  Future<void> _deleteUpload(int id, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Upload'),
        content: const Text('Are you sure you want to delete this upload? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final uri = Uri.parse('${widget.serverUrl}/resumption/$id');
      final response = await http.delete(uri);
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload deleted successfully')),
        );
        
        setState(() {
          _uploads.removeAt(index);
        });
      } else {
        throw Exception('Failed to delete upload');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete upload: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _navigateToAddUpload() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UploadPage(
          uploadType: widget.uploadType,
          serverUrl: widget.serverUrl,
        ),
      ),
    ).then((value) {
      if (value == true) {
        _refreshUploads();
      }
    });
  }

  void _navigateToDetail(ResumptionUpload upload) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResumptionDetailPage(
          uploadId: upload.id,
          serverUrl: widget.serverUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumption Uploads'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshUploads,
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddUpload,
        child: const Icon(Icons.add),
        tooltip: 'Add New Resumption',
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _uploads.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_hasError && _uploads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error loading uploads',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refreshUploads,
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_uploads.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No resumption uploads yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Click the + button to add your first resumption upload',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _navigateToAddUpload,
              icon: const Icon(Icons.add),
              label: const Text('Create First Upload'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshUploads,
      child: NotificationListener<ScrollNotification>(
        onNotification: (ScrollNotification scrollInfo) {
          if (scrollInfo is ScrollEndNotification &&
              scrollInfo.metrics.pixels == scrollInfo.metrics.maxScrollExtent &&
              !_isLoadingMore &&
              _hasMore) {
            _loadMore();
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: _uploads.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _uploads.length) {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final upload = _uploads[index];
            return _buildUploadItem(upload, index);
          },
        ),
      ),
    );
  }

  Widget _buildUploadItem(ResumptionUpload upload, int index) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.description, color: Colors.blue),
        ),
        title: Text(
          upload.projectName.isNotEmpty ? upload.projectName : 'No Project Name',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              upload.contractorName.isNotEmpty ? upload.contractorName : 'No Contractor Name',
              style: const TextStyle(fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              'Uploaded: ${_formatDate(upload.createdAt)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            if (upload.notes != null && upload.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                upload.notes!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'delete') {
              _deleteUpload(upload.id as int, index);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        ),
        onTap: () => _navigateToDetail(upload),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today at ${_formatTime(date)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday at ${_formatTime(date)}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}