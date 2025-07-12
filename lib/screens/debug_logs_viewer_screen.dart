import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../services/debug_service.dart';
import '../widgets/app_drawer.dart';

class DebugLogsViewerScreen extends StatefulWidget {
  const DebugLogsViewerScreen({super.key});

  @override
  State<DebugLogsViewerScreen> createState() => _DebugLogsViewerScreenState();
}

class _DebugLogsViewerScreenState extends State<DebugLogsViewerScreen> {
  final Logger _logger = Logger();
  final DebugService _debugService = DebugService();
  final TextEditingController _searchController = TextEditingController();
  List<String> _logLines = [];
  bool _isLoading = true;
  String _filterTag = 'ALL';
  List<String> _availableTags = ['ALL'];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadLogs() {
    setState(() {
      _isLoading = true;
    });

    try {
      final logs = _debugService.getBufferAsString();
      if (logs.isNotEmpty) {
        _logLines =
            logs.split('\n').where((line) => line.trim().isNotEmpty).toList();

        // Extract available tags - handle both [TAG:xxx] and [xxx] formats
        final tags = <String>{'ALL'};
        for (final line in _logLines) {
          // Try new format first: [TAG:xxx]
          final tagMatch = RegExp(r'\[TAG:([^\]]+)\]').firstMatch(line);
          if (tagMatch != null) {
            tags.add(tagMatch.group(1)!);
            continue;
          }

          // Try old format: [xxx] (but not timestamp format)
          final oldTagMatch = RegExp(r'\[([A-Z]{2,})\]').firstMatch(line);
          if (oldTagMatch != null) {
            final potentialTag = oldTagMatch.group(1)!;
            // Skip if it looks like a timestamp or log level
            if (!potentialTag.contains(':') &&
                !['ERROR', 'WARN', 'INFO', 'DEBUG', 'LOG']
                    .contains(potentialTag)) {
              tags.add(potentialTag);
            }
          }
        }
        _availableTags = tags.toList()..sort();
      } else {
        _logLines = [];
      }
    } catch (e) {
      _logger.e('Error loading logs: $e');
      _logLines = ['Error loading logs: $e'];
    }

    setState(() {
      _isLoading = false;
    });
  }

  List<String> get _filteredLogs {
    List<String> filtered = _logLines;

    // Filter by tag
    if (_filterTag != 'ALL') {
      filtered = filtered.where((line) {
        // Check for new format: [TAG:xxx]
        if (line.contains('[TAG:$_filterTag]')) {
          return true;
        }
        // Check for old format: [xxx]
        if (line.contains('[$_filterTag]')) {
          return true;
        }
        return false;
      }).toList();
    }

    // Filter by search text
    final searchText = _searchController.text.trim().toLowerCase();
    if (searchText.isNotEmpty) {
      filtered = filtered
          .where((line) => line.toLowerCase().contains(searchText))
          .toList();
    }

    return filtered;
  }

  Color _getLogLevelColor(String line) {
    if (line.contains('[ERROR]')) return const Color(0xFFF44336);
    if (line.contains('[WARN]')) return const Color(0xFFFF9800);
    if (line.contains('[INFO]')) return const Color(0xFF2196F3);
    if (line.contains('[DEBUG]')) return const Color(0xFF4CAF50);
    return const Color(0xFF7F8C8D);
  }

  String _getLogLevel(String line) {
    if (line.contains('[ERROR]')) return 'ERROR';
    if (line.contains('[WARN]')) return 'WARN';
    if (line.contains('[INFO]')) return 'INFO';
    if (line.contains('[DEBUG]')) return 'DEBUG';
    return 'LOG';
  }

  String _getLogMessage(String line) {
    // Remove timestamp and tags for cleaner display
    String message = line;

    // Remove timestamp pattern [YYYY-MM-DD HH:mm:ss.mmm]
    message = message.replaceAll(
        RegExp(r'\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\]'), '');

    // Remove new tag pattern [TAG:xxx]
    message = message.replaceAll(RegExp(r'\[TAG:[^\]]+\]'), '');

    // Remove old tag pattern [xxx] (but be careful not to remove log levels)
    message = message.replaceAllMapped(RegExp(r'\[([A-Z]{2,})\]'), (match) {
      final tag = match.group(1)!;
      // Don't remove log levels
      if (['ERROR', 'WARN', 'INFO', 'DEBUG', 'LOG'].contains(tag)) {
        return match.group(0)!;
      }
      return '';
    });

    // Remove log level pattern [LEVEL]
    message = message.replaceAll(RegExp(r'\[(ERROR|WARN|INFO|DEBUG)\]'), '');

    return message.trim();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text(
          'Debug Logs',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: const Color(0xFF1E5979),
        elevation: 0,
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadLogs,
            tooltip: 'Refresh Logs',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Section
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.search,
                      color: Color(0xFF1E5979),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Search Logs:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Enter search term...',
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF7F8C8D),
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF7F8C8D),
                      size: 20,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Color(0xFF7F8C8D),
                              size: 20,
                            ),
                            onPressed: _clearSearch,
                            tooltip: 'Clear Search',
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E6ED)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E6ED)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E5979)),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8F9FA),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF2C3E50),
                  ),
                ),
              ],
            ),
          ),

          // Filter Section
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.filter_list,
                  color: Color(0xFF1E5979),
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Filter by Tag:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filterTag,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      items: _availableTags.map((tag) {
                        return DropdownMenuItem<String>(
                          value: tag,
                          child: Text(
                            tag,
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _filterTag = newValue;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Logs Section
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF1E5979)),
                      ),
                    )
                  : _filteredLogs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _searchController.text.isNotEmpty ||
                                        _filterTag != 'ALL'
                                    ? Icons.search_off
                                    : Icons.info_outline,
                                size: 48,
                                color: const Color(0xFF7F8C8D),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isNotEmpty ||
                                        _filterTag != 'ALL'
                                    ? 'No matching logs found'
                                    : 'No logs available',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF7F8C8D),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchController.text.isNotEmpty ||
                                        _filterTag != 'ALL'
                                    ? 'Try adjusting your search or filter criteria'
                                    : 'Debug logs will appear here when available',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF7F8C8D),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredLogs.length,
                          itemBuilder: (context, index) {
                            final line = _filteredLogs[index];
                            final level = _getLogLevel(line);
                            final message = _getLogMessage(line);
                            final color = _getLogLevelColor(line);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: color.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      level,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      message,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF2C3E50),
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ),

          // Summary Section
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Logs: ${_filteredLogs.length}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    Text(
                      'Filter: $_filterTag',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF7F8C8D),
                      ),
                    ),
                  ],
                ),
                if (_searchController.text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.search,
                        size: 16,
                        color: Color(0xFF7F8C8D),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Search: "${_searchController.text}"',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7F8C8D),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
