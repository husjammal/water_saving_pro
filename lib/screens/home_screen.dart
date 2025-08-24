import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import '../models/connection_state_model.dart';
import '../models/data_state_model.dart';
import '../utils/dialog_utils.dart';
import '../widgets/app_drawer.dart';
import 'reports_screen.dart';
import 'live_charts_screen.dart';
import 'retrieve_data_screen.dart';
import 'settings_screen.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'dart:async';
import 'bluetooth_scan_dialog.dart';
import '../models/data_retrieval_service.dart';
import '../services/sound_service.dart';
import '../services/debug_service.dart';
import '../services/navigation_service.dart';

final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, RouteAware {
  final Logger _logger = Logger();
  String _utcOffset = '+3';
  final DataRetrievalService _dataRetrievalService = DataRetrievalService();

  ConnectionStateModel? _connectionModel;
  StreamSubscription<List<dynamic>>? _liveDataSubscription;
  List<dynamic>? _latestLiveData;
  bool _isStartingLiveData = false;
  bool _shouldAutoStartLiveData = true; // Flag to control auto-start behavior

  // Flow detection variables
  bool _isWaterFlowing = false;
  double _lastFlowRate = 0.0;
  DateTime? _flowStartTime;
  DateTime? _flowStopTime;
  Duration? _lastFlowDuration;

  // Sound service
  final SoundService _soundService = SoundService();
  final DebugService _debugService = DebugService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissions();
    _logger.i('HomeScreenState initialized');
    // Removed Provider.of<DataStateModel>(context, listen: false).loadPersistedData(); from here
  }

  bool _didLoadPersistedData = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Register with RouteObserver
    routeObserver.subscribe(this, ModalRoute.of(context)! as PageRoute);
    _connectionModel =
        Provider.of<ConnectionStateModel>(context, listen: false);
    if (!_didLoadPersistedData) {
      Provider.of<DataStateModel>(context, listen: false).loadPersistedData();
      _didLoadPersistedData = true;
    }
    // Update NavigationService to reflect we're on home screen
    NavigationService().updateCurrentScreen('home');
    // Only restart live data if auto-start is enabled
    _unsubscribeFromLiveData();
    if (_connectionModel?.isConnected == true && _shouldAutoStartLiveData) {
      _startLiveDataIfConnected();
    } else {
      // Not connected: clear latest live data
      setState(() {
        _latestLiveData = null;
      });
    }
  }

  void _subscribeToLiveData() {
    _liveDataSubscription?.cancel();
    final connectionModel = _connectionModel;
    if (connectionModel != null) {
      _logger.i('Subscribing to live data stream...');
      _liveDataSubscription = connectionModel.liveDataStream.listen(
        (data) {
          setState(() {
            _latestLiveData = data;
            _detectFlowChange(data);
          });
        },
        onError: (error) {
          _logger.e('Live data stream error: $error');
        },
        onDone: () {
          _logger.i('Live data stream completed');
        },
      );
      _logger.i('Live data subscription established');
    } else {
      _logger.w('Cannot subscribe to live data: connectionModel is null');
    }
  }

  void _detectFlowChange(List<dynamic> data) {
    if (data.length >= 2) {
      double currentFlowRate = (data[1] as num).toDouble();
      double batteryVoltage =
          data.length >= 3 ? (data[2] as num).toDouble() : 0.0;
      double tapDuration = data.length >= 4 ? (data[3] as num).toDouble() : 0.0;

      // Debug logging for live data
      _debugService.logWaterFlow(currentFlowRate, tag: 'LIVE');
      _debugService.logBattery(batteryVoltage, tag: 'LIVE');
      _debugService.logTapDuration(tapDuration, tag: 'LIVE');

      // Detect flow start (transition from 0 to > 0)
      if (!_isWaterFlowing && currentFlowRate > 0.0) {
        _isWaterFlowing = true;
        _flowStartTime = DateTime.now();
        _flowStopTime = null;
        _lastFlowDuration = null; // Reset duration for new flow
        _logger.i(
            'Water flow started at ${_flowStartTime!.toString().substring(11, 19)}');
        _debugService.logFlow('Water flow STARTED', tag: 'LIVE');

        // Play water flow start sound
        _soundService.playWaterFlowStart();
      }
      // Detect flow stop (transition from > 0 to 0)
      else if (_isWaterFlowing && currentFlowRate == 0.0) {
        _isWaterFlowing = false;
        _flowStopTime = DateTime.now();
        _logger.i(
            'Water flow stopped at ${_flowStopTime!.toString().substring(11, 19)}');
        _debugService.logFlow('Water flow STOPPED', tag: 'LIVE');

        // Play water flow stop sound
        _soundService.playWaterFlowStop();

        // Log flow duration if we have start time
        if (_flowStartTime != null) {
          _lastFlowDuration = _flowStopTime!.difference(_flowStartTime!);
          _logger.i('Flow duration: ${_lastFlowDuration!.inSeconds} seconds');
          _debugService.logFlow(
              'Flow duration: ${_lastFlowDuration!.inSeconds}s',
              tag: 'LIVE');
        }
      }

      _lastFlowRate = currentFlowRate;
    }
  }

  void _unsubscribeFromLiveData() {
    if (_liveDataSubscription != null) {
      _logger.i('Unsubscribing from live data stream...');
      _liveDataSubscription?.cancel();
      _liveDataSubscription = null;
      _logger.i('Live data subscription cancelled');
    }
  }

  void _startLiveDataIfConnected() async {
    final connectionModel = _connectionModel;
    if (connectionModel != null &&
        connectionModel.isConnected &&
        !_isStartingLiveData) {
      _isStartingLiveData = true;
      _logger.i('Starting live data if connected...');
      // Add a small delay to prevent rapid command succession
      await Future.delayed(const Duration(milliseconds: 500));
      await _startLiveData();
      _subscribeToLiveData();
      _isStartingLiveData = false;
      _logger.i('Live data started and subscription established');
    } else {
      _logger.i(
          'Cannot start live data: connected=${connectionModel?.isConnected}, isStarting=$_isStartingLiveData');
    }
  }

  Future<void> _showMessageDialog(
      BuildContext context, String title, String? message) async {
    if (mounted) {
      await DialogUtils.showMessageDialog(
        context: context,
        title: title,
        message: message ?? 'No message',
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
      DialogUtils.showErrorDialog(
          context: context,
          title: 'Permission Error',
          message: 'Failed to request permissions: $e');
    }
  }

  Future<bool> _writeCommand(String command) async {
    if (!mounted) return false;
    return await _connectionModel?.writeCommand(command) ?? false;
  }

  Future<void> _syncTime() async {
    if (!mounted) return;
    final connectionModel = _connectionModel;
    if (connectionModel == null || !connectionModel.isConnected) {
      _logger.w('Cannot sync time: Not connected');
      if (mounted) {
        DialogUtils.showErrorDialog(
            context: context,
            title: 'Sync Error',
            message: 'Please connect to the device first');
      }
      return;
    }
    // Send UTC timestamp without offset - Adafruit expects UTC
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    await _writeCommand('SYNC:$now');
    _logger.i('Sent SYNC:$now (UTC)');
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      DialogUtils.showSuccessDialog(
          context: context,
          title: 'Time Synchronized',
          message: 'Device time synchronized to $now (UTC)');
    }
  }

  Future<void> _saveCsvData() async {
    if (!mounted) return;
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
        DialogUtils.showSuccessDialog(
          context: context,
          title: 'Data Saved',
          message: 'Data saved to ${file.path} with ${result['rowCount']} rows '
              '(${result['duplicateCount']} duplicates and ${result['filteredCount']} old/future rows removed)',
        );
      }
    } catch (e) {
      _logger.e('Error saving CSV: $e');
      if (mounted) {
        DialogUtils.showErrorDialog(
            context: context,
            title: 'CSV Error',
            message: 'Failed to save data: $e');
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
    if (!mounted) return;
    await _connectionModel?.disconnectDevice();
    if (mounted) {
      DialogUtils.showInfoDialog(
          context: context,
          title: 'Disconnected',
          message: 'Disconnected from device');
    }
  }

  Future<void> _readDeviceTime() async {
    if (!mounted) return;
    final connectionModel = _connectionModel;
    if (connectionModel == null || !connectionModel.isConnected) {
      _logger.w('Cannot read device time: Not connected');
      if (mounted) {
        DialogUtils.showErrorDialog(
            context: context,
            title: 'Device Time Error',
            message: 'Please connect to the device first');
      }
      return;
    }
    try {
      connectionModel.updateDeviceTime('Reading...');
      bool success = await _writeCommand('GET_TIME');
      if (!success) {
        connectionModel.updateDeviceTime('Not available');
        if (mounted) {
          DialogUtils.showErrorDialog(
              context: context,
              title: 'Device Time Error',
              message: 'Failed to send GET_TIME command');
        }
      }
    } catch (e) {
      _logger.e('Failed to read device time: $e');
      connectionModel.updateDeviceTime('Not available');
      if (mounted) {
        DialogUtils.showErrorDialog(
            context: context,
            title: 'Device Time Error',
            message: 'Failed to read device time: $e');
      }
    }
  }

  Future<void> _startLiveData() async {
    if (!mounted) return;
    final connectionModel = _connectionModel;
    if (connectionModel == null || !connectionModel.isConnected) {
      _logger.w('Cannot start live data: Not connected');
      return;
    }
    await _writeCommand('START_LIVE_DATA');
    _logger.i('Sent START_LIVE_DATA');
  }

  Future<void> _stopLiveData() async {
    if (!mounted) return;
    final connectionModel = _connectionModel;
    if (connectionModel == null || !connectionModel.isConnected) {
      _logger.w('Cannot stop live data: Not connected');
      return;
    }
    _logger.i('[STOP_LIVE_DATA] Sending STOP_LIVE_DATA to device');
    await _writeCommand('STOP_LIVE_DATA');
    _logger.i('Sent STOP_LIVE_DATA');
  }

  void _disableAutoStartLiveData() {
    _shouldAutoStartLiveData = false;
    _logger.i('Auto-start live data disabled');
  }

  void _enableAutoStartLiveData() {
    _shouldAutoStartLiveData = true;
    _logger.i('Auto-start live data enabled');
  }

  Future<void> _navigateToLiveCharts() async {
    if (!mounted) return;
    final connectionModel = _connectionModel;
    await _startLiveData();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveChartsScreen(
          liveDataStream:
              connectionModel?.liveDataStream ?? const Stream.empty(),
        ),
      ),
    );
    // After returning from LiveChartsScreen, ensure live data is resumed and subscription is active
    if (mounted && connectionModel != null && connectionModel.isConnected) {
      print('[DEBUG] Returned from LiveChartsScreen: (Re)starting live data');
      _startLiveDataIfConnected();
    }
  }

  Future<void> _setManualTimestamp(BuildContext dialogContext) async {
    if (!mounted) return;
    final dataModel = Provider.of<DataStateModel>(context, listen: false);

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
        DialogUtils.showErrorDialog(
            context: context,
            title: 'Timestamp Error',
            message: 'Failed to open date picker: $e');
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
        DialogUtils.showErrorDialog(
            context: context,
            title: 'Timestamp Error',
            message: 'Failed to open time picker: $e');
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
        DialogUtils.showWarningDialog(
            context: context,
            title: 'Timestamp Error',
            message: 'Cannot set timestamp to future time');
      }
      return;
    }

    if (mounted) {
      await dataModel
          .updateLastTimestamp(selectedDateTime.millisecondsSinceEpoch ~/ 1000);
      DialogUtils.showSuccessDialog(
        context: context,
        title: 'Timestamp Updated',
        message:
            'Last timestamp set to ${selectedDateTime.toString().substring(0, 16)}',
      );
      _logger.i('Completed setManualTimestamp: ${dataModel.lastTimestamp}');
    }
  }

  Future<bool> _showConfirmCleanDialog(BuildContext context) async {
    return await DialogUtils.showConfirmDialog(
      context: context,
      title: 'Confirm Clean CSV',
      message:
          'Are you sure you want to clean the CSV file? This will remove duplicates and data older than 6 months.',
      confirmText: 'Confirm',
      cancelText: 'Cancel',
      icon: Icons.cleaning_services,
      iconColor: const Color(0xFF1E5979),
    );
  }

  Future<bool> _showConfirmClearDialog(BuildContext context) async {
    return await DialogUtils.showConfirmDialog(
      context: context,
      title: 'Confirm Clear CSV',
      message:
          'Are you sure you want to clear the CSV file? This action cannot be undone.',
      confirmText: 'Confirm',
      cancelText: 'Cancel',
      icon: Icons.delete_forever,
      iconColor: const Color(0xFFF44336),
      confirmColor: const Color(0xFFF44336),
    );
  }

  Future<void> _showProgressDialog(BuildContext context) async {
    if (mounted) {
      DialogUtils.showProgressDialog(
        context: context,
        message: 'Downloading data...',
      );
    }
  }

  Future<void> _showResultDialog(
      BuildContext context, bool success, String message) async {
    if (mounted) {
      Navigator.of(context, rootNavigator: false).pop();
      if (success) {
        await DialogUtils.showSuccessDialog(
          context: context,
          title: 'Download Complete',
          message: message,
        );
      } else {
        await DialogUtils.showErrorDialog(
          context: context,
          title: 'Download Failed',
          message: message,
        );
      }
    }
  }

  Future<void> _retrieveData() async {
    if (!mounted) return;
    final dataModel = Provider.of<DataStateModel>(context, listen: false);
    _logger.i(
        'Preparing to retrieve data with lastTimestamp: ${dataModel.lastTimestamp}');

    final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (dataModel.lastTimestamp >= currentTimestamp - 5) {
      _logger.w(
          'Warning: lastTimestamp (${dataModel.lastTimestamp}) is close to current time ($currentTimestamp), possible overwrite');
    }

    if (dataModel.lastTimestamp == 0) {
      _logger.w('No valid timestamp found, retrieving all data');
      if (mounted) {
        await DialogUtils.showInfoDialog(
          context: context,
          title: 'Data Retrieval',
          message:
              'No previous data found. Retrieving all available data from device.',
        );
      }
    }

    String command = 'GET_DATA since ${dataModel.lastTimestamp}';
    await _dataRetrievalService.fetchData(context, command);
  }

  Future<void> _retrieveAllData() async {
    _logger.i('Preparing to retrieve all data (GET_DATA since 0)');
    if (mounted) {
      await DialogUtils.showInfoDialog(
          context: context,
          title: 'Data Retrieval',
          message: 'Retrieving all data...');
    }
    String command =
        'GET_DATA since 0 file'; // Add 'file' keyword for file transfer
    await _dataRetrievalService.fetchFileData(context, command,
        isFullRetrieval: true);
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
        if (mounted) {
          DialogUtils.showSuccessDialog(
              context: context,
              title: 'Data Cleared',
              message: 'CSV file cleared successfully');
        }
      } else {
        _logger.i('No CSV file to clear');
        if (mounted) {
          DialogUtils.showInfoDialog(
              context: context,
              title: 'Data Cleared',
              message: 'No CSV file to clear');
        }
      }
    } catch (e) {
      _logger.e('Error clearing CSV: $e');
      if (mounted) {
        DialogUtils.showErrorDialog(
            context: context,
            title: 'CSV Error',
            message: 'Failed to clear CSV file: $e');
      }
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
    routeObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _unsubscribeFromLiveData();
    _stopLiveData(); // Stop live data when leaving HomeScreen
    _soundService.dispose(); // Dispose sound service
    // Example: If you need to disconnect device on dispose, use _connectionModel
    // _connectionModel?.disconnectDevice();
    _logger.i('HomeScreen disposed');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App is backgrounded or not visible
      _logger.i('App backgrounded or inactive: stopping live data');
      _stopLiveData();
      _unsubscribeFromLiveData();
    } else if (state == AppLifecycleState.resumed) {
      // App is foregrounded
      if (_connectionModel?.isConnected == true) {
        _logger.i('App resumed: (Re)starting live data');
        _startLiveDataIfConnected();
      }
    }
  }

  @override
  void didPushNext() {
    // HomeScreen is covered by another route
    _logger.i('HomeScreen covered by another route: stopping live data');
    _stopLiveData();
    _unsubscribeFromLiveData();
  }

  @override
  void didPopNext() {
    // HomeScreen is visible again
    _logger.i('HomeScreen visible again: checking live data status');
    if (_connectionModel?.isConnected == true && _shouldAutoStartLiveData) {
      _logger.i('HomeScreen visible again: (Re)starting live data');
      // First, ensure we're unsubscribed to avoid duplicate subscriptions
      _unsubscribeFromLiveData();
      // Add a small delay to ensure previous commands are processed
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _startLiveDataIfConnected();
          // Ensure subscription is established
          if (_liveDataSubscription == null) {
            _logger.i('Subscription was null, re-establishing...');
            _subscribeToLiveData();
          }
        }
      });
    } else {
      _logger
          .i('HomeScreen visible again: not connected or auto-start disabled');
      // Clear any stale data
      setState(() {
        _latestLiveData = null;
      });
    }
  }

  Widget _buildDashboardCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return _AnimatedDashboardButton(
      title: title,
      icon: icon,
      iconColor: iconColor,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionStateModel>(
      builder: (context, connectionModel, child) {
        // Start live data and subscribe when connected (only if auto-start is enabled)
        if (connectionModel.isConnected &&
            _liveDataSubscription == null &&
            _shouldAutoStartLiveData) {
          _startLiveDataIfConnected();
        } else if (!connectionModel.isConnected &&
            _liveDataSubscription != null) {
          _unsubscribeFromLiveData();
        }

        return WillPopScope(
          onWillPop: () async {
            // If we're on the home screen, show a confirmation dialog before closing the app
            if (ModalRoute.of(context)?.isCurrent == true) {
              bool shouldPop = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => Dialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Icon
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF44336).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.exit_to_app,
                                color: Color(0xFFF44336),
                                size: 48,
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Title
                            const Text(
                              'Exit Application',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Message
                            const Text(
                              'Are you sure you want to close the Water Monitor application?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF7F8C8D),
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFF8F9FA),
                                      foregroundColor: const Color(0xFF7F8C8D),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(
                                          color: const Color(0xFFE0E6ED),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFF44336),
                                      foregroundColor: Colors.white,
                                      elevation: 2,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text(
                                      'Exit',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ) ??
                  false;
              return shouldPop;
            }
            return true; // Allow back navigation for other screens
          },
          child: Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            drawer: AppDrawer(
              onDisableAutoStartLiveData: _disableAutoStartLiveData,
              onEnableAutoStartLiveData: _enableAutoStartLiveData,
              onNavigateToRetrieveData: () async {
                await _soundService.playNotificationSound();
                _disableAutoStartLiveData();
                NavigationService().updateCurrentScreen('retrieve_data');
                Navigator.push(
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
                ).then((_) {
                  _enableAutoStartLiveData();
                });
              },
              onNavigateToSettings: () async {
                await _soundService.playNotificationSound();
                _disableAutoStartLiveData();
                NavigationService().updateCurrentScreen('settings');
                Navigator.push(
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
                ).then((_) {
                  _enableAutoStartLiveData();
                });
              },
            ),
            body: CustomScrollView(
              slivers: [
                // Custom App Bar
                SliverAppBar(
                  expandedHeight: 200,
                  floating: false,
                  pinned: true,
                  backgroundColor: const Color(0xFF1E5979),
                  elevation: 0,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(30),
                    ),
                  ),
                  leading: Builder(
                    builder: (context) => IconButton(
                      icon:
                          const Icon(Icons.menu, size: 36, color: Colors.white),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF1E5979),
                            Color(0xFF2C5F7A),
                            Color(0xFF3A6580),
                          ],
                        ),
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(30),
                        ),
                      ),
                      child: Stack(
                        children: [
                          // Background Pattern
                          Positioned.fill(
                            child: CustomPaint(
                              painter: BackgroundPatternPainter(),
                            ),
                          ),
                          // Content
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.water_drop,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Water Monitor',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            'Smart Water Management',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                // Connection Status
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: connectionModel.isConnected
                                        ? Colors.green.withOpacity(0.2)
                                        : Colors.red.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: connectionModel.isConnected
                                          ? Colors.green
                                          : Colors.red,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: connectionModel.isConnected
                                              ? Colors.green
                                              : Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        connectionModel.connectionStatus,
                                        style: TextStyle(
                                          color: connectionModel.isConnected
                                              ? Colors.green
                                              : Colors.red,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    title: const Text(
                      'Dashboard',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    centerTitle: true,
                  ),
                ),

                // Main Content
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Live Data Card with Animation
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 1000),
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, value, child) {
                            return Transform.translate(
                              offset: Offset(0, 50 * (1 - value)),
                              child: Opacity(
                                opacity: value,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 24),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white,
                                        const Color(0xFFF8F9FA),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    const Color(0xFF2196F3),
                                                    const Color(0xFF1976D2),
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: const Icon(
                                                Icons.sensors,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Text(
                                              'Live Data',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF2C3E50),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _buildDataItem(
                                                icon: Icons.access_time,
                                                label: 'Timestamp',
                                                value: (connectionModel
                                                            .isConnected &&
                                                        _latestLiveData != null)
                                                    ? DateFormat('HH:mm:ss')
                                                        .format(
                                                        DateTime.fromMillisecondsSinceEpoch(
                                                                _latestLiveData![
                                                                        0] *
                                                                    1000)
                                                            .toLocal(),
                                                      )
                                                    : '--',
                                                color: const Color(0xFF1E5979),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: _buildDataItem(
                                                icon: _isWaterFlowing
                                                    ? Icons.water_drop
                                                    : Icons.water_drop_outlined,
                                                label: 'Flow Rate',
                                                value: (connectionModel
                                                            .isConnected &&
                                                        _latestLiveData != null)
                                                    ? '${(_latestLiveData![1] * 60).toStringAsFixed(2)} L/min'
                                                    : '--',
                                                color: _isWaterFlowing
                                                    ? const Color(0xFF2196F3)
                                                    : const Color(0xFF7F8C8D),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _buildDataItem(
                                                icon: Icons.battery_full,
                                                label: 'Battery',
                                                value: (connectionModel
                                                            .isConnected &&
                                                        _latestLiveData != null)
                                                    ? '${_latestLiveData![2].toStringAsFixed(2)}V'
                                                    : '--',
                                                color: const Color(0xFF4CAF50),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: _buildDataItem(
                                                icon: Icons.touch_app,
                                                label: 'Tap On/OFF',
                                                value: (connectionModel
                                                            .isConnected &&
                                                        _latestLiveData != null)
                                                    ? _latestLiveData![3]
                                                        .toStringAsFixed(1)
                                                    : '--',
                                                color: const Color(0xFFF44336),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        // Flow Status Card (only show when connected)
                        if (connectionModel.isConnected)
                          TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 1400),
                            tween: Tween(begin: 0.0, end: 1.0),
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(0, 50 * (1 - value)),
                                child: Opacity(
                                  opacity: value,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          _isWaterFlowing
                                              ? const Color(0xFFE3F2FD)
                                              : const Color(0xFFF5F5F5),
                                          _isWaterFlowing
                                              ? const Color(0xFFBBDEFB)
                                              : const Color(0xFFEEEEEE),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _isWaterFlowing
                                            ? const Color(0xFF2196F3)
                                            : const Color(0xFF9E9E9E),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (_isWaterFlowing
                                                  ? const Color(0xFF2196F3)
                                                  : const Color(0xFF9E9E9E))
                                              .withOpacity(0.1),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: _isWaterFlowing
                                                  ? const Color(0xFF2196F3)
                                                  : const Color(0xFF9E9E9E),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              _isWaterFlowing
                                                  ? Icons.water_drop
                                                  : Icons.water_drop_outlined,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _isWaterFlowing
                                                      ? 'Water is Flowing'
                                                      : 'Water is Stopped',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: _isWaterFlowing
                                                        ? const Color(
                                                            0xFF1976D2)
                                                        : const Color(
                                                            0xFF616161),
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                if (_isWaterFlowing &&
                                                    _flowStartTime != null)
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Started at ${DateFormat('HH:mm:ss').format(_flowStartTime!)}',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: _isWaterFlowing
                                                              ? const Color(
                                                                  0xFF1976D2)
                                                              : const Color(
                                                                  0xFF616161),
                                                        ),
                                                      ),
                                                      Text(
                                                        'Duration: ${DateTime.now().difference(_flowStartTime!).inSeconds}s',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: _isWaterFlowing
                                                              ? const Color(
                                                                  0xFF1976D2)
                                                              : const Color(
                                                                  0xFF616161),
                                                        ),
                                                      ),
                                                    ],
                                                  )
                                                else if (!_isWaterFlowing &&
                                                    _flowStopTime != null)
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        'Stopped at ${DateFormat('HH:mm:ss').format(_flowStopTime!)}',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: _isWaterFlowing
                                                              ? const Color(
                                                                  0xFF1976D2)
                                                              : const Color(
                                                                  0xFF616161),
                                                        ),
                                                      ),
                                                      if (_lastFlowDuration !=
                                                          null)
                                                        Text(
                                                          'Duration: ${_lastFlowDuration!.inSeconds}s',
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: _isWaterFlowing
                                                                ? const Color(
                                                                    0xFF1976D2)
                                                                : const Color(
                                                                    0xFF616161),
                                                          ),
                                                        ),
                                                    ],
                                                  )
                                                else
                                                  Text(
                                                    'Monitoring water flow...',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: _isWaterFlowing
                                                          ? const Color(
                                                              0xFF1976D2)
                                                          : const Color(
                                                              0xFF616161),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _isWaterFlowing
                                                  ? const Color(0xFF2196F3)
                                                  : const Color(0xFF9E9E9E),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              _isWaterFlowing
                                                  ? 'ACTIVE'
                                                  : 'IDLE',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                        // Connect Button with Animation
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 1200),
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, value, child) {
                            return Transform.translate(
                              offset: Offset(0, 50 * (1 - value)),
                              child: Opacity(
                                opacity: value,
                                child: _AnimatedConnectButton(
                                  isConnected: connectionModel.isConnected,
                                  onTap: () => showBluetoothScanDialog(
                                    context: context,
                                    onConnect: (device) {
                                      Provider.of<ConnectionStateModel>(context,
                                              listen: false)
                                          .connectToDevice(
                                        device,
                                        () async {
                                          if (mounted) {
                                            await Future.delayed(
                                                const Duration(seconds: 1));
                                            _syncTime();
                                          }
                                        },
                                        context,
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        // Dashboard Card with 4 buttons
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 1000),
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, value, child) {
                            return Transform.translate(
                              offset: Offset(0, 50 * (1 - value)),
                              child: Opacity(
                                opacity: value,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 24),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white,
                                        const Color(0xFFF8F9FA),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    const Color(0xFF1E5979),
                                                    const Color(0xFF2C5F7A),
                                                  ],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: const Icon(
                                                Icons.dashboard,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Text(
                                              'Dashboard',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF2C3E50),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        GridView.count(
                                          crossAxisCount: 2,
                                          shrinkWrap: true,
                                          physics:
                                              const NeverScrollableScrollPhysics(),
                                          crossAxisSpacing: 16,
                                          mainAxisSpacing: 16,
                                          childAspectRatio: 1.1,
                                          children: [
                                            _buildDashboardCard(
                                              title: 'Retrieve Data',
                                              icon: Icons.cloud_download,
                                              iconColor: Color(0xFF2196F3),
                                              onTap: () async {
                                                await _soundService
                                                    .playNotificationSound();
                                                _disableAutoStartLiveData();
                                                NavigationService()
                                                    .updateCurrentScreen(
                                                        'retrieve_data');
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        RetrieveDataScreen(
                                                      onRetrieveData:
                                                          _retrieveData,
                                                      onRetrieveAllData:
                                                          _retrieveAllData,
                                                      onSetManualTimestamp:
                                                          _setManualTimestamp,
                                                      onClearCsvData:
                                                          _clearCsvData,
                                                      onCleanCsvData:
                                                          _cleanCsvData,
                                                    ),
                                                  ),
                                                ).then((_) {
                                                  _enableAutoStartLiveData();
                                                });
                                              },
                                            ),
                                            _buildDashboardCard(
                                              title: 'View Reports',
                                              icon: Icons.bar_chart,
                                              iconColor: Color(0xFFF44336),
                                              onTap: () async {
                                                await _soundService
                                                    .playNotificationSound();
                                                _disableAutoStartLiveData();
                                                NavigationService()
                                                    .updateCurrentScreen(
                                                        'reports');
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) => Consumer<
                                                        DataStateModel>(
                                                      builder: (context,
                                                              dataModel,
                                                              child) =>
                                                          const ReportsScreen(),
                                                    ),
                                                  ),
                                                ).then((_) {
                                                  _enableAutoStartLiveData();
                                                });
                                              },
                                            ),
                                            _buildDashboardCard(
                                              title: 'Live Charts',
                                              icon: Icons.show_chart,
                                              iconColor: Color(0xFF4CAF50),
                                              onTap: () async {
                                                await _soundService
                                                    .playNotificationSound();
                                                NavigationService()
                                                    .updateCurrentScreen(
                                                        'live_charts');
                                                _navigateToLiveCharts();
                                              },
                                            ),
                                            _buildDashboardCard(
                                              title: 'Settings',
                                              icon: Icons.settings,
                                              iconColor: Color(0xFFFF9800),
                                              onTap: () async {
                                                await _soundService
                                                    .playNotificationSound();
                                                _disableAutoStartLiveData();
                                                NavigationService()
                                                    .updateCurrentScreen(
                                                        'settings');
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        SettingsScreen(
                                                      utcOffset: _utcOffset,
                                                      onDisconnectDevice:
                                                          _disconnectDevice,
                                                      onSyncTime: _syncTime,
                                                      onReadDeviceTime:
                                                          _readDeviceTime,
                                                      onUpdateUtcOffset:
                                                          (value) {
                                                        setState(() {
                                                          _utcOffset = value;
                                                        });
                                                        _logger.i(
                                                            'UTC offset changed to: $_utcOffset');
                                                      },
                                                    ),
                                                  ),
                                                ).then((_) {
                                                  _enableAutoStartLiveData();
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
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

  Widget _buildDataItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool showStatus = false,
    String? statusText,
    Color? statusColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (showStatus && statusText != null && statusColor != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C3E50),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Painter for Background Pattern
class BackgroundPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 1;

    // Draw diagonal lines
    for (int i = 0; i < size.width + size.height; i += 30) {
      canvas.drawLine(
        Offset(i.toDouble(), 0),
        Offset(0, i.toDouble()),
        paint,
      );
    }

    // Draw circles
    final circlePaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.2),
      40,
      circlePaint,
    );

    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.8),
      60,
      circlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Animated dashboard button widget
class _AnimatedDashboardButton extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  const _AnimatedDashboardButton({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  State<_AnimatedDashboardButton> createState() =>
      _AnimatedDashboardButtonState();
}

class _AnimatedDashboardButtonState extends State<_AnimatedDashboardButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.0,
      upperBound: 0.1,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnim.value,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    const Color(0xFFF8F9FA),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: widget.onTap,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                widget.iconColor.withOpacity(0.15),
                                widget.iconColor.withOpacity(0.07),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            widget.icon,
                            size: 32,
                            color: widget.iconColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2C3E50),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// Animated Connect Button widget
class _AnimatedConnectButton extends StatefulWidget {
  final bool isConnected;
  final VoidCallback onTap;
  const _AnimatedConnectButton(
      {required this.isConnected, required this.onTap});

  @override
  State<_AnimatedConnectButton> createState() => _AnimatedConnectButtonState();
}

class _AnimatedConnectButtonState extends State<_AnimatedConnectButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.0,
      upperBound: 0.1,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnim.value,
            child: Container(
              width: double.infinity,
              height: 50,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.isConnected
                      ? [const Color(0xFF4CAF50), const Color(0xFF45A049)]
                      : [const Color(0xFF1E5979), const Color(0xFF2C5F7A)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: (widget.isConnected
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFF1E5979))
                        .withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: widget.onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.isConnected
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_searching,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.isConnected ? 'Connected' : 'Connect Device',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
