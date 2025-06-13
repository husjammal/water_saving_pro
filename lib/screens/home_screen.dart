import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import '../models/connection_state_model.dart';
import '../models/data_state_model.dart';
import 'reports_screen.dart';
import 'live_charts_screen.dart';
import 'retrieve_data_screen.dart';
import 'settings_screen.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Logger _logger = Logger();
  String _utcOffset = '+0';

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _logger.i('HomeScreenState initialized');
    Provider.of<DataStateModel>(context, listen: false).loadPersistedData();
  }

  Future<void> _showMessageDialog(
      BuildContext context, String title, String? message) async {
    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: Text(title),
            content: Text(message ?? 'No message'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
      _logger.i('Showed dialog: $title: $message');
    }
  }


  Future<void> _requestPermissions() async {
    try {
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
        Permission.storage,
      ].request();
      _logger.i('Permissions requested');
    } catch (e) {
      _logger.e('Permission request failed: $e');
      _showMessageDialog(
          context, 'Permission Error', 'Failed to request permissions: $e');
    }
  }

  Future<bool> _writeCommand(String command) async {
    return await Provider.of<ConnectionStateModel>(context, listen: false)
        .writeCommand(command);
  }

  Future<void> _syncTime() async {
    final connectionModel =
        Provider.of<ConnectionStateModel>(context, listen: false);
    if (!connectionModel.isConnected) {
      _logger.w('Cannot sync time: Not connected');
      _showMessageDialog(
          context, 'Sync Error', 'Please connect to the device first');
      return;
    }
    final offsetHours = int.parse(_utcOffset.replaceFirst('+', ''));
    final offsetSeconds = offsetHours * 3600;
    final now = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + offsetSeconds;
    await _writeCommand('SYNC:$now');
    _logger.i('Sent SYNC:$now with UTC offset $_utcOffset');
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      _showMessageDialog(context, 'Time Synchronized',
          'Device time synchronized to $now with UTC offset $_utcOffset');
    }
  }

  Future<void> _saveCsvData() async {
    final dataModel = Provider.of<DataStateModel>(context, listen: false);
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

      _logger.i('Saved CSV file: '
          'Path: ${file.path}, '
          'Rows: ${result['rowCount']}, '
          'Size: $fileSizeKB KB ($fileSize bytes), '
          'Saved at: $saveTime, '
          'Duplicates removed: ${result['duplicateCount']}, '
          'Filtered rows: ${result['filteredCount']}');

      if (mounted) {
        Navigator.of(context, rootNavigator: false).pop();
        _showMessageDialog(
          context,
          'Data Saved',
          'Data saved to ${file.path} with ${result['rowCount']} rows '
              '(${result['duplicateCount']} duplicates and ${result['filteredCount']} old/future rows removed)',
        );
      }
    } catch (e) {
      _logger.e('Error saving CSV: $e');
      if (mounted) {
        Navigator.of(context, rootNavigator: false).pop();
        _showMessageDialog(context, 'CSV Error', 'Failed to save data: $e');
      }
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
    _logger.i(
        'Filtered $filteredCount rows (older than 6 months or future timestamps)');

    final uniqueRows = <String, List<dynamic>>{};
    for (var row in filteredData) {
      uniqueRows[row.join(',')] = row;
    }
    filteredData = uniqueRows.values.toList();
    int duplicateCount = originalCount - filteredCount - filteredData.length;
    _logger.i(
        'Removed $duplicateCount duplicate rows, unique rows: ${filteredData.length}');

    filteredData.sort((a, b) => (a[0] as int).compareTo(b[0] as int));
    _logger.i('Sorted ${filteredData.length} rows by timestamp');

    return {
      'data': filteredData,
      'duplicateCount': duplicateCount,
      'filteredCount': filteredCount,
      'rowCount': filteredData.length,
    };
  }

  Future<void> _disconnectDevice() async {
    await Provider.of<ConnectionStateModel>(context, listen: false)
        .disconnectDevice();
    if (mounted) {
      _showMessageDialog(context, 'Disconnected', 'Disconnected from device');
    }
  }

  Future<void> _readDeviceTime() async {
    final connectionModel =
        Provider.of<ConnectionStateModel>(context, listen: false);
    if (!connectionModel.isConnected) {
      _logger.w('Cannot read device time: Not connected');
      _showMessageDialog(
          context, 'Device Time Error', 'Please connect to the device first');
      return;
    }
    try {
      connectionModel.updateDeviceTime('Reading...');
      bool success = await _writeCommand('GET_TIME');
      if (!success) {
        connectionModel.updateDeviceTime('Not available');
        _showMessageDialog(
            context, 'Device Time Error', 'Failed to send GET_TIME command');
      }
    } catch (e) {
      _logger.e('Failed to read device time: $e');
      connectionModel.updateDeviceTime('Not available');
      _showMessageDialog(
          context, 'Device Time Error', 'Failed to read device time: $e');
    }
  }

  Future<void> _startLiveData() async {
    final connectionModel =
        Provider.of<ConnectionStateModel>(context, listen: false);
    if (!connectionModel.isConnected) {
      _logger.w('Cannot start live data: Not connected');
      return;
    }
    await _writeCommand('START_LIVE_DATA');
    _logger.i('Sent START_LIVE_DATA');
  }

  Future<void> _stopLiveData() async {
    final connectionModel =
        Provider.of<ConnectionStateModel>(context, listen: false);
    if (!connectionModel.isConnected) {
      _logger.w('Cannot stop live data: Not connected');
      return;
    }
    await _writeCommand('STOP_LIVE_DATA');
    _logger.i('Sent STOP_LIVE_DATA');
  }

  Future<void> _navigateToLiveCharts() async {
    final connectionModel =
        Provider.of<ConnectionStateModel>(context, listen: false);
    await _startLiveData();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveChartsScreen(
          liveDataStream: connectionModel.liveDataStream,
        ),
      ),
    );
    await _stopLiveData();
  }

  Future<void> _setManualTimestamp(BuildContext dialogContext) async {
    final dataModel = Provider.of<DataStateModel>(context, listen: false);
    if (!mounted) {
      _logger.w('Cannot show date picker: HomeScreen widget not mounted');
      return;
    }

    _logger.i('Starting setManualTimestamp');
    final now = DateTime.now();
    final firstDate = DateTime(2020);
    final lastDate = now;

    DateTime initialDate;
    if (dataModel.lastTimestamp == 0) {
      initialDate = lastDate;
      _logger
          .d('No last timestamp, setting initialDate to lastDate: $lastDate');
    } else {
      final timestampDate =
          DateTime.fromMillisecondsSinceEpoch(dataModel.lastTimestamp * 1000);
      if (timestampDate.isAfter(lastDate) ||
          timestampDate.isBefore(firstDate)) {
        _logger.w(
            'Invalid lastTimestamp: ${dataModel.lastTimestamp}, results in $timestampDate, setting initialDate to lastDate: $lastDate');
        initialDate = lastDate;
      } else {
        initialDate = timestampDate;
        _logger.d(
            'Valid lastTimestamp: ${dataModel.lastTimestamp}, setting initialDate to $initialDate');
      }
    }

    DateTime? date;
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      _logger.d('Showing date picker with initialDate: $initialDate');
      date = await showDatePicker(
        context: dialogContext,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      );
      _logger.d('Date picker result: $date');
    } catch (e) {
      _logger.e('Failed to show date picker: $e');
      if (mounted) {
        _showMessageDialog(
            context, 'Timestamp Error', 'Failed to open date picker: $e');
      }
      return;
    }

    if (date == null || !mounted) {
      _logger.i('Date picker cancelled or widget not mounted');
      return;
    }

    TimeOfDay? time;
    try {
      _logger.d('Showing time picker');
      time = await showTimePicker(
        context: dialogContext,
        initialTime: dataModel.lastTimestamp == 0
            ? TimeOfDay.fromDateTime(now)
            : TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(
                dataModel.lastTimestamp * 1000)),
      );
      _logger.d('Time picker result: $time');
    } catch (e) {
      _logger.e('Failed to show time picker: $e');
      if (mounted) {
        _showMessageDialog(
            context, 'Timestamp Error', 'Failed to open time picker: $e');
      }
      return;
    }

    if (time == null || !mounted) {
      _logger.i('Time picker cancelled or widget not mounted');
      return;
    }

    final selectedDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    final nowTruncated =
        DateTime(now.year, now.month, now.day, now.hour, now.minute);
    final selectedTruncated = DateTime(
      selectedDateTime.year,
      selectedDateTime.month,
      selectedDateTime.day,
      selectedDateTime.hour,
      selectedDateTime.minute,
    );

    if (selectedTruncated.isAfter(nowTruncated)) {
      _logger.w('Attempted to set future timestamp: $selectedDateTime');
      if (mounted) {
        _showMessageDialog(
            context, 'Timestamp Error', 'Cannot set timestamp to future time');
      }
      return;
    }

    if (mounted) {
      await dataModel
          .updateLastTimestamp(selectedDateTime.millisecondsSinceEpoch ~/ 1000);
      _showMessageDialog(
        context,
        'Timestamp Updated',
        'Last timestamp set to ${selectedDateTime.toString().substring(0, 16)}',
      );
      _logger.i('Completed setManualTimestamp: ${dataModel.lastTimestamp}');
    }
  }

  Future<bool> _showConfirmCleanDialog(BuildContext context) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('Confirm Clean CSV'),
          content: const Text(
              'Are you sure you want to clean the CSV file? This will remove duplicates and data older than 6 months.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    return confirmed ?? false;
  }

  Future<bool> _showConfirmClearDialog(BuildContext context) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('Confirm Clear CSV'),
          content: const Text(
            'Are you sure you want to clear the CSV file? This action cannot be undone.',
            style: TextStyle(color: Colors.red),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _showProgressDialog(BuildContext context) async {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Downloading data...'),
              ],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _showResultDialog(
      BuildContext context, bool success, String message) async {
    if (mounted) {
      Navigator.of(context, rootNavigator: false).pop();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: Text(success ? 'Download Complete' : 'Download Failed'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _fetchData(String command,
      {bool isFullRetrieval = false}) async {
    final connectionModel =
        Provider.of<ConnectionStateModel>(context, listen: false);
    final dataModel = Provider.of<DataStateModel>(context, listen: false);
    if (!connectionModel.isConnected) {
      _logger.w('Cannot retrieve data: Not connected');
      if (mounted) {
        Navigator.of(context, rootNavigator: false).pop();
        _showMessageDialog(context, 'Data Retrieval Error',
            'Please connect to the device first');
      }
      return;
    }
    _logger.i(
        'Starting fetchData with command: $command, isFullRetrieval: $isFullRetrieval');

    await _showProgressDialog(context);

    try {
      int initialRowCount = dataModel.csvData.length;
      await _writeCommand(command);
      _logger.i('Sent command: $command');

      await Future.delayed(const Duration(seconds: 60));

      int newRows = dataModel.csvData.length - initialRowCount;
      String message;
      if (newRows > 0) {
        _logger.i(
            'Received $newRows new rows, lastTimestamp updated to ${dataModel.lastTimestamp}');
        message = 'Successfully retrieved $newRows new rows.';
      } else {
        _logger.i('No new data received for command: $command');
        message = 'No new data available';
      }

      await _saveCsvData();
      await _showResultDialog(context, true, 'Data saved with $newRows rows');
    } catch (e) {
      _logger.e('Failed to retrieve data: $e');
      await _showResultDialog(context, false, 'Failed to retrieve data: $e');
    }
  }

  Future<void> _retrieveData() async {
    final dataModel = Provider.of<DataStateModel>(context, listen: false);
    _logger.i(
        'Preparing to retrieve data with lastTimestamp: ${dataModel.lastTimestamp}');
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _logger.i('Current timestamp: $currentTimestamp');
    if (dataModel.lastTimestamp >= currentTimestamp - 5) {
      _logger.w(
          'Warning: lastTimestamp (${dataModel.lastTimestamp}) is close to current time ($currentTimestamp), possible overwrite');
    }

    if (dataModel.lastTimestamp == 0) {
      _logger.w('No valid timestamp found, retrieving all data');
      await _showMessageDialog(
        context,
        'Data Retrieval',
        'No previous data found. Retrieving all available data from device.',
      );
    }
    String command = 'GET_DATA since ${dataModel.lastTimestamp}';
    await _fetchData(command);
  }

  Future<void> _retrieveAllData() async {
    _logger.i('Preparing to retrieve all data (GET_DATA since 0)');
    await _showMessageDialog(
        context, 'Data Retrieval', 'Retrieving all data...');
    String command = 'GET_DATA since 0';
    await _fetchData(command, isFullRetrieval: true);
  }

  Future<void> _clearCsvData() async {
    bool confirmed = await _showConfirmClearDialog(context);
    if (!confirmed) {
      _logger.i('CSV clearing cancelled by user');
      return;
    }

    try {
      final file = File('/storage/emulated/0/Documents/water_data.csv');
      bool exists = await file.exists();
      if (exists) {
        await file.delete();
        await Provider.of<DataStateModel>(context, listen: false)
            .clearCsvData();
        _logger.i('Cleared CSV file, reset lastTimestamp to 0');
        _showMessageDialog(
            context, 'Data Cleared', 'CSV file cleared successfully');
      } else {
        _logger.i('No CSV file to clear');
        _showMessageDialog(context, 'Data Cleared', 'No CSV file to clear');
      }
    } catch (e) {
      _logger.e('Error clearing CSV: $e');
      _showMessageDialog(context, 'CSV Error', 'Failed to clear CSV file: $e');
    }
  }

  Future<Map<String, dynamic>> _cleanCsvData(BuildContext context) async {
    bool confirmed = await _showConfirmCleanDialog(context);
    if (!confirmed) {
      _logger.i('CSV cleaning cancelled by user');
      return {
        'success': false,
        'message': 'CSV cleaning was cancelled',
      };
    }

    final dataModel = Provider.of<DataStateModel>(context, listen: false);
    try {
      const documentsPath = '/storage/emulated/0/Documents';
      final file = File('$documentsPath/water_data.csv');
      if (!await file.exists() || dataModel.csvData.isEmpty) {
        _logger.i('No data to clean: File does not exist or is empty');
        return {
          'success': false,
          'message': 'No data available to clean',
        };
      }

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

      _logger.i('Cleaned CSV file: '
          'Path: ${file.path}, '
          'Rows: ${result['rowCount']}, '
          'Size: $fileSizeKB KB ($fileSize bytes), '
          'Saved at: $saveTime, '
          'Duplicates removed: ${result['duplicateCount']}, '
          'Filtered rows: ${result['filteredCount']}');

      return summary;
    } catch (e) {
      _logger.e('Error cleaning CSV: $e');
      return {
        'success': false,
        'message': 'Failed to clean CSV: $e',
      };
    }
  }

  @override
  void dispose() {
    _logger.i('HomeScreen disposed');
    super.dispose();
  }

  Widget _buildDashboardCard({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: Theme.of(context).primaryColor),
              const SizedBox(height: 8),
              Text(
                title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionStateModel>(
      builder: (context, connectionModel, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Water Monitor Dashboard'),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(50),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Status: ',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    Flexible(
                      child: Text(
                        connectionModel.connectionStatus,
                        style: TextStyle(
                          color: connectionModel.isConnected
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          overflow: TextOverflow.ellipsis,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                _buildDashboardCard(
                  title: 'Retrieve Data',
                  icon: Icons.cloud_download,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RetrieveDataScreen(
                        onRetrieveData: _retrieveData,
                        onRetrieveAllData: _retrieveAllData,
                        onSetManualTimestamp: _setManualTimestamp,
                        onClearCsvData: _clearCsvData,
                        onCleanCsvData: _cleanCsvData,
                      ),
                    ),
                  ),
                ),
                _buildDashboardCard(
                  title: 'View Reports',
                  icon: Icons.bar_chart,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Consumer<DataStateModel>(
                        builder: (context, dataModel, child) => const ReportsScreen(),
                      ),
                    ),
                  ),
                ),
                _buildDashboardCard(
                  title: 'View Live Charts',
                  icon: Icons.show_chart,
                  onTap: _navigateToLiveCharts,
                ),
                _buildDashboardCard(
                  title: 'Settings',
                  icon: Icons.settings,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        utcOffset: _utcOffset,
                        onDisconnectDevice: _disconnectDevice,
                        onSyncTime: _syncTime,
                        onReadDeviceTime: _readDeviceTime,
                        onUpdateUtcOffset: (value) {
                          setState(() {
                            _utcOffset = value;
                          });
                          _logger.i('UTC offset changed to: $_utcOffset');
                        },
                      ),
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
