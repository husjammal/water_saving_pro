import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:convert';

class RetrieveDataScreen extends StatefulWidget {
  final List<List<dynamic>> csvData;
  final int lastTimestamp;
  final Future<int> Function() onRetrieveData;
  final Future<int> Function() onRetrieveAllData;
  final void Function(BuildContext) onSetManualTimestamp;
  final VoidCallback onClearCsvData;
  final Future<Map<String, dynamic>> Function(BuildContext) onCleanCsvData;

  const RetrieveDataScreen({
    super.key,
    required this.csvData,
    required this.lastTimestamp,
    required this.onRetrieveData,
    required this.onRetrieveAllData,
    required this.onSetManualTimestamp,
    required this.onClearCsvData,
    required this.onCleanCsvData,
  });

  @override
  State<RetrieveDataScreen> createState() => _RetrieveDataScreenState();
}

class _RetrieveDataScreenState extends State<RetrieveDataScreen> {
  late int _lastTimestamp;
  late List<List<dynamic>> _csvData;
  Map<String, dynamic>? _csvSummary;

  @override
  void initState() {
    super.initState();
    _lastTimestamp = widget.lastTimestamp;
    _csvData = widget.csvData;
    _loadCsvSummary();
  }

  Future<void> _loadCsvSummary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final summaryJson = prefs.getString('csvSummary');
      if (summaryJson != null) {
        setState(() {
          _csvSummary = jsonDecode(summaryJson);
        });
      }
    } catch (e) {
      print('Failed to load CSV summary: $e');
    }
  }

  Future<void> _shareCsvFile() async {
    try {
      const documentsPath = '/storage/emulated/0/Documents';
      final file = File('$documentsPath/water_data.csv');
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Water Data CSV',
          text: 'Sharing water_data.csv from Water Monitor App',
        );
        print('Share initiated for ${file.path}');
      } else {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Share Error'),
            content: const Text('No CSV file found to share.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('Failed to share CSV: $e');
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Share Error'),
          content: Text('Failed to share CSV: $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retrieve Data'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Data Retrieval',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final newTimestamp = await widget.onRetrieveData();
                        setState(() {
                          _lastTimestamp = newTimestamp;
                          _csvData = widget.csvData;
                        });
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('Retrieve Data'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final newTimestamp = await widget.onRetrieveAllData();
                        setState(() {
                          _lastTimestamp = newTimestamp;
                          _csvData = widget.csvData;
                        });
                      },
                      icon: const Icon(Icons.all_inclusive),
                      label: const Text('Retrieve All Data'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _lastTimestamp == 0
                          ? 'No last timestamp'
                          : 'Last timestamp: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(_lastTimestamp * 1000))}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Data Management',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Builder(
                      builder: (buttonContext) => ElevatedButton.icon(
                        onPressed: () {
                          widget.onSetManualTimestamp(buttonContext);
                          setState(() {
                            _lastTimestamp = widget.lastTimestamp;
                          });
                        },
                        icon: const Icon(Icons.calendar_today),
                        label: const Text('Set Last Timestamp'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: widget.onClearCsvData,
                      icon: const Icon(Icons.delete),
                      label: const Text('Clear CSV'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final result = await widget.onCleanCsvData(context);
                        setState(() {
                          _lastTimestamp = widget.lastTimestamp;
                          _csvData = widget.csvData;
                          if (result['success'] == true) {
                            _csvSummary = result;
                          }
                        });
                        if (result['success'] == true) {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('CSV Cleaned'),
                              content: Text(
                                'CSV file cleaned successfully:\n'
                                'Path: ${result['path']}\n'
                                'Rows: ${result['rowCount']}\n'
                                'Size: ${result['fileSizeKB']} KB (${result['fileSizeBytes']} bytes)\n'
                                'Saved at: ${result['saveTime']}\n'
                                'Duplicates removed: ${result['duplicateCount']}\n'
                                'Old/Future rows removed: ${result['filteredCount']}',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        } else {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('CSV Error'),
                              content: Text(result['message'] as String),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.cleaning_services),
                      label: const Text('Clean CSV'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _shareCsvFile,
                      icon: const Icon(Icons.share),
                      label: const Text('Share CSV'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Total records: ${_csvData.length}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CSV Summary',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    if (_csvSummary == null)
                      const Text(
                        'No CSV summary available',
                        style: TextStyle(fontSize: 14),
                      )
                    else if (_csvSummary!['success'] == false)
                      Text(
                        'Status: ${_csvSummary!['message']}',
                        style: const TextStyle(fontSize: 14),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Path: ${_csvSummary!['path']}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            'Rows: ${_csvSummary!['rowCount']}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            'Size: ${_csvSummary!['fileSizeKB']} KB (${_csvSummary!['fileSizeBytes']} bytes)',
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            'Saved at: ${_csvSummary!['saveTime']}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            'Duplicates removed: ${_csvSummary!['duplicateCount']}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            'Old/Future rows removed: ${_csvSummary!['filteredCount']}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
