// Replace the entire PertListPage.dart with this:

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'pert_upload_page.dart';
import 'pert_detail_page.dart'; // You'll need to create this

class PertListPage extends StatefulWidget {
  final String serverUrl;
  final int initialLimit;

  const PertListPage({
    super.key,
    required this.serverUrl,
    this.initialLimit = 20,
  });

  @override
  State<PertListPage> createState() => _PertListPageState();
}

class _PertListPageState extends State<PertListPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _error = false;
  String _errorMessage = '';
  int _page = 1;
  late int _limit;
  bool _hasMore = true;
  bool _loadingMore = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String get listPath => '/pert/list';

  @override
  void initState() {
    super.initState();
    _limit = widget.initialLimit;
    _fetchList();
  }

  Future<void> _fetchList({bool loadMore = false, bool resetSearch = false}) async {
    if (!loadMore || resetSearch) {
      setState(() {
        _loading = true;
        _error = false;
        _errorMessage = '';
        _page = 1;
        _hasMore = true;
        if (resetSearch) {
          _items.clear();
        }
      });
    } else {
      setState(() {
        _loadingMore = true;
      });
    }

    try {
      final Map<String, String> queryParams = {
        'page': _page.toString(),
        'limit': _limit.toString(),
      };

      if (_searchQuery.isNotEmpty) {
        queryParams['search'] = _searchQuery;
      }

      final uri = Uri.parse('${widget.serverUrl}$listPath').replace(
        queryParameters: queryParams,
      );

      print('Fetching PERT list from: $uri');

      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }

      final Map<String, dynamic> j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (j['ok'] != true) {
        throw Exception(j['error'] ?? 'Failed to load PERT submissions');
      }

      final uploads = (j['uploads'] is List) 
          ? List<Map<String, dynamic>>.from(j['uploads']) 
          : <Map<String, dynamic>>[];

      setState(() {
        if (loadMore && !resetSearch) {
          _items.addAll(uploads);
        } else {
          _items = uploads;
        }
        _hasMore = uploads.length == _limit;
        _error = false;
      });
    } catch (e) {
      print('Error fetching PERT list: $e');
      setState(() {
        _error = true;
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _refresh() async {
    _page = 1;
    await _fetchList(resetSearch: true);
  }

  Future<void> _loadMoreIfNeeded() async {
    if (!_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    _page++;
    await _fetchList(loadMore: true);
  }

  void _openDetail(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PertDetailPage(uploadId: id, serverUrl: widget.serverUrl),
      ),
    );
  }

  void _openAdd([PertMode? mode]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PertUploadPage(initialMode: mode),
      ),
    ).then((value) {
      // Refresh list when returning from upload page
      if (value == true) {
        _refresh();
      }
    });
  }

  Future<void> _deleteItem(String id, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete PERT Submission'),
        content: const Text('Are you sure you want to delete this PERT submission?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final uri = Uri.parse('${widget.serverUrl}/pert/$id');
      final resp = await http.delete(uri);
      
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PERT submission deleted')),
        );
        setState(() {
          _items.removeAt(index);
        });
      } else {
        throw Exception('Delete failed: ${resp.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting: $e')),
      );
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return 'No date';
    try {
      final d = DateTime.parse(iso).toLocal();
      final day = d.day.toString().padLeft(2, '0');
      final month = d.month.toString().padLeft(2, '0');
      final year = d.year;
      final hour = d.hour.toString().padLeft(2, '0');
      final min = d.minute.toString().padLeft(2, '0');
      return '$day/$month/$year $hour:$min';
    } catch (e) {
      return iso;
    }
  }

  String _getUploadTypeDisplay(String? type) {
    if (type == null) return 'PERT';
    if (type.contains('Original')) return 'Original';
    if (type.contains('Revised')) return 'Revised';
    return type;
  }

  Color _getTypeColor(String? type) {
    if (type == null) return Colors.blue;
    if (type.contains('Original')) return Colors.green;
    if (type.contains('Revised')) return Colors.orange;
    return Colors.blue;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PERT / PDM Submissions'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            onPressed: () => _openAdd(PertMode.original),
            icon: const Icon(Icons.add),
            label: const Text('Original'),
            backgroundColor: Colors.green,
            heroTag: 'original_fab',
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            onPressed: () => _openAdd(PertMode.revised),
            icon: const Icon(Icons.update),
            label: const Text('Revised'),
            backgroundColor: Colors.orange,
            heroTag: 'revised_fab',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 12),
              const Text(
                'Failed to load PERT submissions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(_errorMessage, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _refresh,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.schedule, size: 64, color: Colors.grey),
              const SizedBox(height: 12),
              const Text(
                'No PERT / PDM submissions found',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isNotEmpty
                    ? 'Try a different search term'
                    : 'Start by adding a new submission',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _openAdd(PertMode.original),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Original'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openAdd(PertMode.revised),
                    icon: const Icon(Icons.update),
                    label: const Text('Add Revised'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search contractor or project...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _searchQuery = '';
                        _refresh();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onSubmitted: (value) {
              _searchQuery = value.trim();
              _refresh();
            },
          ),
        ),
        // List Count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_items.length} ${_items.length == 1 ? 'submission' : 'submissions'}',
                style: TextStyle(color: Colors.grey[600]),
              ),
              if (_searchQuery.isNotEmpty)
                Chip(
                  label: Text('Search: "$_searchQuery"'),
                  deleteIcon: const Icon(Icons.close),
                  onDeleted: () {
                    _searchController.clear();
                    _searchQuery = '';
                    _refresh();
                  },
                ),
            ],
          ),
        ),
        // List
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollEndNotification &&
                    notification.metrics.pixels ==
                        notification.metrics.maxScrollExtent &&
                    !_loadingMore &&
                    _hasMore) {
                  _loadMoreIfNeeded();
                }
                return false;
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: _items.length + (_loadingMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (index == _items.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final item = _items[index];
                  final id = (item['id'] ?? '').toString();
                  final project = (item['project_name'] ?? '').toString();
                  final contractor = (item['contractor_name'] ?? '').toString();
                  final createdAt = (item['created_at'] ?? '').toString();
                  final uploadType = (item['upload_type'] ?? '').toString();
                  final fileCount = (item['file_count'] ?? 0) as int;
                  final certifier = (item['certifier_name'] ?? '').toString();

                  return Card(
                    elevation: 2,
                    child: ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _getTypeColor(uploadType).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          uploadType.contains('Revised')
                              ? Icons.update
                              : Icons.insert_drive_file,
                          color: _getTypeColor(uploadType),
                        ),
                      ),
                      title: Text(
                        project.isNotEmpty ? project : '(No project name)',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (contractor.isNotEmpty)
                            Text(
                              contractor,
                              style: const TextStyle(fontSize: 14),
                            ),
                          if (certifier.isNotEmpty)
                            Text(
                              'Certified by: $certifier',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Chip(
                                label: Text(
                                  _getUploadTypeDisplay(uploadType),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: _getTypeColor(uploadType),
                                  ),
                                ),
                                backgroundColor:
                                    _getTypeColor(uploadType).withOpacity(0.1),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 0),
                              ),
                              const SizedBox(width: 8),
                              Chip(
                                label: Text(
                                  '$fileCount file${fileCount != 1 ? 's' : ''}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                backgroundColor: Colors.grey[200],
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 0),
                              ),
                            ],
                          ),
                          Text(
                            _formatDate(createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'open') _openDetail(id);
                          if (value == 'delete') _deleteItem(id, index);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'open',
                            child: Row(
                              children: [
                                Icon(Icons.visibility, size: 18),
                                SizedBox(width: 8),
                                Text('View Details'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _openDetail(id),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}