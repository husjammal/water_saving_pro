import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import '../utils/dialog_utils.dart';
import 'connection_state_model.dart';
import 'data_state_model.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:intl/intl.dart';

class DataRetrievalService {
  final Logger _logger = Logger();

  Future<void> fetchData(
    BuildContext context,
    String command, {
    bool isFullRetrieval = false,
  }) async {
    final connectionModel =
        Provider.of<ConnectionStateModel>(context, listen: false);
    final dataModel = Provider.of<DataStateModel>(context, listen: false);

    if (!connectionModel.isConnected) {
      _logger.w('Cannot retrieve data: Not connected');
      DialogUtils.showErrorDialog(
          context: context,
          title: 'Data Retrieval Error',
          message: 'Please connect to the device first');
      return;
    }

    _logger.i(
        'Starting fetchData with command: $command, isFullRetrieval: $isFullRetrieval');

    bool retrievalDone = false;
    bool retrievalCancelled = false;
    int totalRows = 0;
    int receivedRows = 0;
    final completer = Completer<void>();
    final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0);
    final ValueNotifier<int> receivedRowsNotifier = ValueNotifier<int>(0);
    final ValueNotifier<int> totalRowsNotifier = ValueNotifier<int>(0);
    final ValueNotifier<bool> transferCompleteNotifier =
        ValueNotifier<bool>(false);
    BuildContext? dialogContext;

    void onLine(String line) {
      _logger.d('onLine received: $line');
      if (line.startsWith('TOTAL_ROWS:')) {
        final parts = line.split(':');
        if (parts.length == 2) {
          totalRows = int.tryParse(parts[1].trim()) ?? 0;
          totalRowsNotifier.value = totalRows;
        }
      } else if (line.trim().toUpperCase().contains('END_OF_DATA')) {
        retrievalDone = true;
        transferCompleteNotifier.value = true;
        if (!completer.isCompleted) {
          completer.complete();
        }
        // Close the dialog automatically
        if (dialogContext != null && Navigator.of(dialogContext!).canPop()) {
          Navigator.of(dialogContext!).pop();
        }
      } else if (line.contains(',') && totalRows > 0) {
        receivedRows++;
        receivedRowsNotifier.value = receivedRows;
        progressNotifier.value = receivedRows / totalRows;
      }
    }

    // Add the line listener BEFORE sending the command
    connectionModel.addLineListener(onLine);

    // Show the progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        dialogContext = ctx;
        return WillPopScope(
          onWillPop: () async => false,
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E5979).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.cloud_download,
                          color: Color(0xFF1E5979),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Retrieving Data',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                            Text(
                              'Downloading data from device',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7F8C8D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Progress Content
                  ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (context, progress, _) {
                      return ValueListenableBuilder<int>(
                        valueListenable: totalRowsNotifier,
                        builder: (context, total, _) {
                          if (total > 0) {
                            final percent = (progress * 100)
                                .clamp(0, 100)
                                .toStringAsFixed(1);
                            return Column(
                              children: [
                                // Progress Bar
                                Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0E6ED),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: progress.clamp(0.0, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF1E5979),
                                            Color(0xFF2196F3)
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Progress Text
                                ValueListenableBuilder<int>(
                                  valueListenable: receivedRowsNotifier,
                                  builder: (context, received, _) {
                                    return Column(
                                      children: [
                                        Text(
                                          '$percent% Complete',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1E5979),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '$received of $total rows downloaded',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF7F8C8D),
                                          ),
                                        ),
                                        const SizedBox(height: 16),

                                        // Status Message
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE8F5E8),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: const Color(0xFF4CAF50)
                                                  .withOpacity(0.3),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.check_circle,
                                                color: Color(0xFF4CAF50),
                                                size: 16,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Downloading data...',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF4CAF50),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                const SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 4,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF1E5979)),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Initializing download...',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2C3E50),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Please wait while we connect to the device',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF7F8C8D),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            );
                          }
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // Send the command
    await connectionModel.writeCommand(command);
    _logger.i('Command sent: $command');

    await completer.future;
    connectionModel.removeLineListener(onLine);

    if (retrievalCancelled) {
      _logger.i('Data retrieval cancelled by user');
      DialogUtils.showInfoDialog(
          context: context,
          title: 'Cancelled',
          message: 'Data retrieval was cancelled.');
      return;
    }

    // Save the data
    await _saveCsvData(context, dataModel);
  }

  Future<void> fetchFileData(
    BuildContext context,
    String command, {
    bool isFullRetrieval = false,
  }) async {
    final connectionModel =
        Provider.of<ConnectionStateModel>(context, listen: false);
    final dataModel = Provider.of<DataStateModel>(context, listen: false);

    if (!connectionModel.isConnected) {
      _logger.w('Cannot retrieve file: Not connected');
      DialogUtils.showErrorDialog(
          context: context,
          title: 'File Retrieval Error',
          message: 'Please connect to the device first');
      return;
    }

    _logger.i(
        'Starting fetchFileData with command: $command, isFullRetrieval: $isFullRetrieval');

    bool fileTransferDone = false;
    bool fileTransferCancelled = false;
    int fileSize = 0;
    int receivedBytes = 0;
    int totalRows = 0;
    int receivedRows = 0;
    final completer = Completer<void>();
    final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0);
    final ValueNotifier<int> receivedBytesNotifier = ValueNotifier<int>(0);
    final ValueNotifier<int> fileSizeNotifier = ValueNotifier<int>(0);
    final ValueNotifier<int> totalRowsNotifier = ValueNotifier<int>(0);
    final ValueNotifier<int> receivedRowsNotifier = ValueNotifier<int>(0);
    final ValueNotifier<bool> transferCompleteNotifier =
        ValueNotifier<bool>(false);
    BuildContext? dialogContext;
    List<int> fileData = [];

    void onData(List<int> data) {
      if (fileSize > 0 && !fileTransferDone) {
        fileData.addAll(data);
        receivedBytes = fileData.length;
        receivedBytesNotifier.value = receivedBytes;
        final chunkStr = utf8.decode(data, allowMalformed: true);
        final newRows = '\n'.allMatches(chunkStr).length;
        receivedRows += newRows;
        receivedRowsNotifier.value = receivedRows;
        if (totalRows > 0) {
          progressNotifier.value = receivedRows / totalRows;
        } else {
          progressNotifier.value = receivedBytes / fileSize;
        }
      }
    }

    void onLine(String line) {
      if (line.startsWith('TOTAL_ROWS:')) {
        final parts = line.split(':');
        if (parts.length == 2) {
          totalRows = int.tryParse(parts[1].trim()) ?? 0;
          totalRowsNotifier.value = totalRows;
        }
      } else if (line.startsWith('FILE_SIZE:')) {
        final parts = line.split(':');
        if (parts.length == 2) {
          fileSize = int.tryParse(parts[1].trim()) ?? 0;
          fileSizeNotifier.value = fileSize;
        }
      } else if (line == 'FILE_START') {
        fileData.clear();
        receivedBytes = 0;
        receivedRows = 0;
      } else if (line == 'FILE_END') {
        fileTransferDone = true;
        transferCompleteNotifier.value = true;
        connectionModel.removeLineListener(onLine);
        connectionModel.removeDataListener(onData);
        if (!completer.isCompleted) {
          completer.complete();
        }
        if (dialogContext != null && Navigator.of(dialogContext!).canPop()) {
          Navigator.of(dialogContext!).pop();
        }
      } else if (line.startsWith('ERROR:')) {
        connectionModel.removeLineListener(onLine);
        connectionModel.removeDataListener(onData);
        if (!completer.isCompleted) {
          completer.completeError(line);
        }
      }
    }

    connectionModel.addLineListener(onLine);
    connectionModel.addDataListener(onData);

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) {
        dialogContext = ctx;
        return WillPopScope(
          onWillPop: () async => false,
          child: Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E5979).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.file_download,
                          color: Color(0xFF1E5979),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'File Transfer',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                            Text(
                              'Receiving data file from device',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7F8C8D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Progress Content
                  ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (context, progress, _) {
                      return ValueListenableBuilder<int>(
                        valueListenable: totalRowsNotifier,
                        builder: (context, total, _) {
                          if (total > 0) {
                            final percent = (progress * 100)
                                .clamp(0, 100)
                                .toStringAsFixed(1);
                            return Column(
                              children: [
                                // Progress Bar
                                Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0E6ED),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: progress.clamp(0.0, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF1E5979),
                                            Color(0xFF2196F3)
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Progress Text
                                ValueListenableBuilder<int>(
                                  valueListenable: receivedRowsNotifier,
                                  builder: (context, received, _) {
                                    return Column(
                                      children: [
                                        Text(
                                          '$percent% Complete',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1E5979),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '$received of $total rows received',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF7F8C8D),
                                          ),
                                        ),
                                        const SizedBox(height: 16),

                                        // Status Message
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE8F5E8),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: const Color(0xFF4CAF50)
                                                  .withOpacity(0.3),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.file_download,
                                                color: Color(0xFF4CAF50),
                                                size: 16,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Receiving file data...',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF4CAF50),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                // Progress Bar
                                Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0E6ED),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: progress.clamp(0.0, 1.0),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF1E5979),
                                            Color(0xFF2196F3)
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Progress Text
                                ValueListenableBuilder<int>(
                                  valueListenable: receivedBytesNotifier,
                                  builder: (context, received, _) {
                                    final percent = (progress * 100)
                                        .clamp(0, 100)
                                        .toStringAsFixed(1);
                                    final receivedKB =
                                        (received / 1024).toStringAsFixed(1);
                                    final totalKB =
                                        (fileSizeNotifier.value / 1024)
                                            .toStringAsFixed(1);

                                    return Column(
                                      children: [
                                        Text(
                                          '$percent% Complete',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1E5979),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '$receivedKB of $totalKB KB received',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF7F8C8D),
                                          ),
                                        ),
                                        const SizedBox(height: 16),

                                        // Status Message
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE8F5E8),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: const Color(0xFF4CAF50)
                                                  .withOpacity(0.3),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.file_download,
                                                color: Color(0xFF4CAF50),
                                                size: 16,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Receiving file...',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF4CAF50),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            );
                          }
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    await connectionModel.writeCommand(command);

    try {
      await completer.future;
    } catch (e) {
      _logger.e('File transfer error: $e');
      DialogUtils.showErrorDialog(
          context: context,
          title: 'File Transfer Error',
          message: 'Failed to receive file: $e');
      return;
    }

    if (fileTransferCancelled) {
      _logger.i('File transfer cancelled by user');
      DialogUtils.showInfoDialog(
          context: context,
          title: 'Cancelled',
          message: 'File transfer was cancelled.');
      return;
    }

    // Save the received file data
    if (fileData.isNotEmpty) {
      try {
        const documentsPath = '/storage/emulated/0/Documents';
        final directory = Directory(documentsPath);
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        final file = File('$documentsPath/water_data.csv');

        await file.writeAsBytes(fileData);

        try {
          String csvContent = utf8.decode(fileData, allowMalformed: true);
          await dataModel.loadDataFromString(csvContent);
        } catch (e) {
          _logger.e('Error decoding CSV content: $e');
        }

        final fileSize = await file.length();
        final saveTime =
            DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
        final fileSizeKB = (fileSize / 1024).toStringAsFixed(2);
        double percent = fileSize > 0 && fileSizeNotifier.value > 0
            ? (fileSize / fileSizeNotifier.value * 100).clamp(0, 100)
            : 100.0;

        await dataModel.loadDataFromFile(file.path);

        DialogUtils.showSuccessDialog(
          context: context,
          title: 'File Received',
          message:
              'File received and saved to ${file.path} ($fileSizeKB KB)\nDownload complete: ${percent.toStringAsFixed(1)}%',
        );
      } catch (e) {
        _logger.e('Error saving received file: $e');
        DialogUtils.showErrorDialog(
            context: context,
            title: 'File Error',
            message: 'Failed to save received file: $e');
      }
    } else {
      _logger.w('No file data received');
      DialogUtils.showErrorDialog(
          context: context,
          title: 'File Error',
          message: 'No file data received from device');
    }
  }

  Future<void> _saveCsvData(
      BuildContext context, DataStateModel dataModel) async {
    try {
      const documentsPath = '/storage/emulated/0/Documents';
      final directory = Directory(documentsPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final file = File('$documentsPath/water_data.csv');

      final result = _processCsvData(dataModel.csvData);

      final sink = file.openWrite();
      sink.write('timestamp,water_flow_rate,battery_voltage,tap_on_duration\n');
      for (var row in result['data']) {
        sink.write('${row.join(',')}\n');
      }
      await sink.flush();
      await sink.close();

      final fileSize = await file.length();
      final saveTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final fileSizeKB = (fileSize / 1024).toStringAsFixed(2);

      final summary = {
        'success': true,
        'path': file.path,
        'rowCount': result['rowCount'],
        'fileSizeKB': fileSizeKB,
        'fileSizeBytes': fileSize,
        'saveTime': saveTime,
        'duplicateCount': result['duplicateCount'],
        'filteredCount': result['filteredCount'],
      };

      await dataModel.updateCsvData(result['data']);
      await dataModel.updateCsvSummary(summary);

      _logger.i(
          'Saved CSV file: Path: ${file.path}, Rows: ${result['rowCount']}, Size: $fileSizeKB KB');

      DialogUtils.showSuccessDialog(
        context: context,
        title: 'Data Saved',
        message: 'Data saved to ${file.path} with ${result['rowCount']} rows '
            '(${result['duplicateCount']} duplicates and ${result['filteredCount']} old/future rows removed)',
      );
    } catch (e) {
      _logger.e('Error saving CSV: $e');
      DialogUtils.showErrorDialog(
          context: context,
          title: 'CSV Error',
          message: 'Failed to save data: $e');
    }
  }

  Map<String, dynamic> _processCsvData(List<List<dynamic>> csvData) {
    int originalCount = csvData.length;

    final now = DateTime.now();
    final sixMonthsAgo = now.subtract(const Duration(days: 182));
    final currentTimestamp = now.millisecondsSinceEpoch ~/ 1000;
    final sixMonthsAgoTimestamp = sixMonthsAgo.millisecondsSinceEpoch ~/ 1000;

    var filteredData = csvData.where((row) {
      int timestamp = row[0] as int;
      return timestamp >= sixMonthsAgoTimestamp &&
          timestamp <= currentTimestamp;
    }).toList();

    int filteredCount = originalCount - filteredData.length;

    final uniqueRows = <String, List<dynamic>>{};
    for (var row in filteredData) {
      uniqueRows[row.join(',')] = row;
    }
    filteredData = uniqueRows.values.toList();
    int duplicateCount = originalCount - filteredCount - filteredData.length;

    filteredData.sort((a, b) => (a[0] as int).compareTo(b[0] as int));

    return {
      'data': filteredData,
      'duplicateCount': duplicateCount,
      'filteredCount': filteredCount,
      'rowCount': filteredData.length,
    };
  }
}
