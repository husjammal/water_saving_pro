import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/data_state_model.dart';
import '../utils/dialog_utils.dart';
import '../widgets/app_drawer.dart';
import 'dart:io';
import '../models/connection_state_model.dart';

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

  @override
  void initState() {
    super.initState();
    // Stop live data when entering retrieve data
    Future.microtask(() async {
      final connectionModel =
          Provider.of<ConnectionStateModel>(context, listen: false);
      if (connectionModel.isConnected) {
        // ignore: avoid_print
        print('[STOP_LIVE_DATA] Sent from RetrieveDataScreen');
        await connectionModel.writeCommand('STOP_LIVE_DATA');
      }
    });
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
        _logger.i('Share initiated for ${file.path}');
      } else {
        DialogUtils.showErrorDialog(
          context: context,
          title: 'Share Error',
          message: 'No CSV file found to share.',
        );
      }
    } catch (e) {
      _logger.e('Failed to share CSV: $e');
      DialogUtils.showErrorDialog(
        context: context,
        title: 'Share Error',
        message: 'Failed to share CSV: $e',
      );
    }
  }

  Future<void> _showRetrieveAllDataWarning() async {
    final confirmed = await DialogUtils.showConfirmDialog(
      context: context,
      title: '⚠️ Large Data Retrieval Warning',
      message:
          'Retrieving all data may take a very long time if the file is large.\n\n'
          '⚠️ IMPORTANT WARNINGS:\n'
          '• Process may take several minutes to hours\n'
          '• Do not disconnect the device during retrieval\n'
          '• If the process halts or freezes:\n'
          '  - Restart the Adafruit device manually\n'
          '  - Restart this application\n'
          '  - Try retrieving data in smaller chunks\n\n'
          'Are you sure you want to proceed with retrieving ALL data?',
      confirmText: 'Yes, Retrieve All',
      cancelText: 'Cancel',
      icon: Icons.warning_amber,
      iconColor: const Color(0xFFFF9800),
      confirmColor: const Color(0xFF4CAF50),
    );

    if (confirmed) {
      _logger.i('User confirmed retrieve all data after warning');
      await widget.onRetrieveAllData();
    } else {
      _logger.i('User cancelled retrieve all data');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DataStateModel>(
      builder: (context, dataModel, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          drawer: const AppDrawer(
            onDisableAutoStartLiveData: null,
            onEnableAutoStartLiveData: null,
            onNavigateToRetrieveData: null,
            onNavigateToSettings: null,
          ),
          appBar: AppBar(
            title: const Text(
              'Retrieve Data',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.exit_to_app, color: Colors.white),
                tooltip: 'Exit',
                onPressed: () {
                  Navigator.maybePop(context);
                },
              ),
            ],
            backgroundColor: const Color(0xFF1E5979),
            elevation: 0,
            centerTitle: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Data Retrieval Card
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2196F3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Data Retrieval',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: widget.onRetrieveData,
                          icon: const Icon(Icons.download, color: Colors.white),
                          label: const Text(
                            'Retrieve Data',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2196F3),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _showRetrieveAllDataWarning,
                          icon: const Icon(Icons.warning_amber,
                              color: Colors.white),
                          label: const Text(
                            'Retrieve All Data',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE0E6ED)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                color: Color(0xFF1E5979),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dataModel.lastTimestamp == 0
                                      ? 'No last timestamp'
                                      : 'Last timestamp: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(dataModel.lastTimestamp * 1000))}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF2C3E50),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Data Management Card
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF44336),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Data Management',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Builder(
                          builder: (buttonContext) => ElevatedButton.icon(
                            onPressed: () =>
                                widget.onSetManualTimestamp(buttonContext),
                            icon: const Icon(Icons.calendar_today,
                                color: Colors.white),
                            label: const Text(
                              'Set Last Timestamp',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E5979),
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: widget.onClearCsvData,
                          icon: const Icon(Icons.delete, color: Colors.white),
                          label: const Text(
                            'Clear CSV',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF44336),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final result = await widget.onCleanCsvData(context);
                            if (result['success'] == true) {
                              DialogUtils.showSuccessDialog(
                                context: context,
                                title: 'CSV Cleaned',
                                message: 'CSV file cleaned successfully:\n'
                                    'Path: ${result['path']}\n'
                                    'Rows: ${result['rowCount']}\n'
                                    'Size: ${result['fileSizeKB']} KB (${result['fileSizeBytes']} bytes)\n'
                                    'Saved at: ${result['saveTime']}\n'
                                    'Duplicates removed: ${result['duplicateCount']}\n'
                                    'Old/Future rows removed: ${result['filteredCount']}',
                              );
                            } else {
                              DialogUtils.showErrorDialog(
                                context: context,
                                title: 'CSV Error',
                                message: result['message'] as String,
                              );
                            }
                          },
                          icon: const Icon(Icons.cleaning_services,
                              color: Colors.white),
                          label: const Text(
                            'Clean CSV',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF9800),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _shareCsvFile,
                          icon: const Icon(Icons.share, color: Colors.white),
                          label: const Text(
                            'Share CSV',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF9C27B0),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE0E6ED)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.storage,
                                color: Color(0xFF1E5979),
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Total records: ${dataModel.csvData.length}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF2C3E50),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // CSV Summary Card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'CSV Summary',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (dataModel.csvSummary == null)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFE0E6ED)),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Color(0xFF7F8C8D),
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'No CSV summary available',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF7F8C8D),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (dataModel.csvSummary!['success'] == false)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFEBEE),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFFFCDD2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Color(0xFFD32F2F),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Status: ${dataModel.csvSummary!['message']}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFFD32F2F),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFE0E6ED)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSummaryRow(
                                    'Path', dataModel.csvSummary!['path']),
                                _buildSummaryRow(
                                    'Rows',
                                    dataModel.csvSummary!['rowCount']
                                        .toString()),
                                _buildSummaryRow('Size',
                                    '${dataModel.csvSummary!['fileSizeKB']} KB (${dataModel.csvSummary!['fileSizeBytes']} bytes)'),
                                _buildSummaryRow('Saved at',
                                    dataModel.csvSummary!['saveTime']),
                                _buildSummaryRow(
                                    'Duplicates removed',
                                    dataModel.csvSummary!['duplicateCount']
                                        .toString()),
                                _buildSummaryRow(
                                    'Old/Future rows removed',
                                    dataModel.csvSummary!['filteredCount']
                                        .toString()),
                              ],
                            ),
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

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF7F8C8D),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF2C3E50),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
