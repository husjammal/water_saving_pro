import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/data_state_model.dart';
import 'dart:io';

class RetrieveDataScreen extends StatefulWidget {
  final Future<void> Function() onRetrieveData;
  final Future<void> Function() onRetrieveAllData;
  final void Function(BuildContext) onSetManualTimestamp;
  final VoidCallback onClearCsvData;
  final Future<Map<String, dynamic>> Function(BuildContext) onCleanCsvData;

  const RetrieveDataScreen({
    super.key,
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
  final Logger _logger = Logger();

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
        _logger.i('Share initiated for ${file.path}');
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
      _logger.e('Failed to share CSV: $e');
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
    return Consumer<DataStateModel>(
      builder: (context, dataModel, child) {
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
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: widget.onRetrieveData,
                          icon: const Icon(Icons.download),
                          label: const Text('Retrieve Data'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: widget.onRetrieveAllData,
                          icon: const Icon(Icons.all_inclusive),
                          label: const Text('Retrieve All Data'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          dataModel.lastTimestamp == 0
                              ? 'No last timestamp'
                              : 'Last timestamp: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(dataModel.lastTimestamp * 1000))}',
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
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Builder(
                          builder: (buttonContext) => ElevatedButton.icon(
                            onPressed: () =>
                                widget.onSetManualTimestamp(buttonContext),
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
                          'Total records: ${dataModel.csvData.length}',
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
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        if (dataModel.csvSummary == null)
                          const Text(
                            'No CSV summary available',
                            style: TextStyle(fontSize: 14),
                          )
                        else if (dataModel.csvSummary!['success'] == false)
                          Text(
                            'Status: ${dataModel.csvSummary!['message']}',
                            style: const TextStyle(fontSize: 14),
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Path: ${dataModel.csvSummary!['path']}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              Text(
                                'Rows: ${dataModel.csvSummary!['rowCount']}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              Text(
                                'Size: ${dataModel.csvSummary!['fileSizeKB']} KB (${dataModel.csvSummary!['fileSizeBytes']} bytes)',
                                style: const TextStyle(fontSize: 14),
                              ),
                              Text(
                                'Saved at: ${dataModel.csvSummary!['saveTime']}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              Text(
                                'Duplicates removed: ${dataModel.csvSummary!['duplicateCount']}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              Text(
                                'Old/Future rows removed: ${dataModel.csvSummary!['filteredCount']}',
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
      },
    );
  }
}
