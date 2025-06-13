import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:csv/csv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'reports_screen.dart';
import 'live_charts_screen.dart';
import 'retrieve_data_screen.dart';
import 'settings_screen.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Logger _logger = Logger();
  String _connectionStatus = 'Disconnected';
  bool _isConnected = false;
  List<List<dynamic>> _csvData = [];
  int _lastTimestamp = 0;
  String _utcOffset = '+0';
  String _deviceTime = 'Not available';
  BluetoothDevice? _device;
  BluetoothCharacteristic? _uartTx;
  BluetoothCharacteristic? _uartRx;
  StreamSubscription<List<int>>? _characteristicSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  String _dataBuffer = '';
  bool _isReceivingData = false;
  String? _pendingRow;
  bool _isFullRetrieval = false;
  final StreamController<List<dynamic>> _liveDataController =
  StreamController<List<dynamic>>.broadcast();
  final String serviceUUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String txUUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
  final String rxUUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadPersistedData();
  }

  Future<void> _showMessageDialog(BuildContext context, String title, String message) async {
    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            title: Text(title),
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

  Future<bool> _showConfirmCleanDialog(BuildContext context) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: const Text('Confirm Clean CSV'),
          content: const Text('Are you sure you want to clean the CSV file? This will remove duplicates and data older than 6 months.'),
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

  Future<void> _requestPermissions() async {
    try {
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
        Permission.storage,
        Permission.manageExternalStorage,
      ].request();
      _logger.i('Permissions requested');
      _connectToDevice();
    } catch (e) {
      _logger.e('Permission request failed: $e');
      _showMessageDialog(context, 'Permission Error', 'Permission request failed: $e');
    }
  }

  Future<void> _loadPersistedData() async {
    await _loadLastTimestamp();
    await _loadCsvData();
  }

  Future<void> _loadCsvData() async {
    try {
      const documentsPath = '/storage/emulated/0/Documents';
      final file = File('$documentsPath/water_data.csv');
      if (await file.exists()) {
        final csvString = await file.readAsString();
        if (csvString.trim().isEmpty) {
          _logger.i('CSV file is empty');
          return;
        }
        final result = await compute(_parseCsv, csvString);
        setState(() {
          _csvData = result['data'];
        });
        _logger.i('Loaded ${_csvData.length} records from CSV');
      } else {
        _logger.i('CSV file does not exist');
      }
    } catch (e) {
      _logger.e('Failed to load CSV: $e');
      _showMessageDialog(context, 'CSV Error', 'Failed to load water_data.csv: $e');
    }
  }

  Future<void> _loadLastTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _lastTimestamp = prefs.getInt('lastTimestamp') ?? 0;
      });
      _logger.i('Loaded lastTimestamp: $_lastTimestamp');
    } catch (e) {
      _logger.e('Failed to load last timestamp: $e');
      _lastTimestamp = 0;
      _showMessageDialog(context, 'Timestamp Error', 'Failed to load last timestamp: $e');
    }
  }

  Future<void> _saveLastTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('lastTimestamp', _lastTimestamp);
      _logger.i('Saved lastTimestamp: $_lastTimestamp');
    } catch (e) {
      _logger.e('Failed to save last timestamp: $e');
      _showMessageDialog(context, 'Timestamp Error', 'Failed to save last timestamp: $e');
    }
  }

  Future<void> _saveCsvSummary(Map<String, dynamic> result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('csvSummary', jsonEncode(result));
      _logger.i('Saved CSV summary: $result');
    } catch (e) {
      _logger.e('Failed to save CSV summary: $e');
    }
  }

  static Map<String, dynamic> _parseCsv(String csvString) {
    final csvList = const CsvToListConverter(
      eol: '\n',
      fieldDelimiter: ',',
    ).convert(csvString);
    if (csvList.isEmpty || (csvList.length == 1 && csvList[0].join(',').startsWith('timestamp'))) {
      return {'data': [], 'lastTimestamp': 0};
    }
    final data = csvList
        .skip(1)
        .map((row) {
      if (row.length >= 4) {
        try {
          int timestamp = int.parse(row[0].toString().trim());
          double flowRate = double.parse(row[1].toString().trim());
          double batteryVoltage = double.parse(row[2].toString().trim());
          double tapOnDuration = double.parse(row[3].toString().trim());
          return [timestamp, flowRate, batteryVoltage, tapOnDuration];
        } catch (e) {
          print('Invalid row: $row, Error: $e');
          return null;
        }
      }
      return null;
    })
        .where((row) => row != null)
        .cast<List<dynamic>>()
        .toList();
    int lastTimestamp = data.isNotEmpty
        ? data.map((row) => row[0] as int).reduce((a, b) => a > b ? a : b)
        : 0;
    return {'data': data, 'lastTimestamp': lastTimestamp};
  }

  Future<void> _startScan() async {
    try {
      if (await FlutterBluePlus.isScanning.first) {
        await FlutterBluePlus.stopScan();
      }
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      _logger.i('Bluetooth scan started');
    } catch (e) {
      _logger.e('Failed to start scan: $e');
      _setConnectionStatus('Scan failed: $e');
      rethrow;
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _scanSubscription = null;
      _logger.i('Bluetooth scan stopped');
    } catch (e) {
      _logger.e('Failed to stop scan: $e');
      rethrow;
    }
  }

  void _setConnectionStatus(String status) {
    if (mounted) {
      setState(() {
        _connectionStatus = status;
        _isConnected = status == 'Connection established';
      });
      _logger.i('Connection status: $status');
      if (status.contains('failed') || status == 'Disconnected') {
        _showMessageDialog(context, 'Connection Status', status);
      }
    }
  }

  Future<void> _connectToDevice() async {
    _setConnectionStatus('Scanning for Adafruit-Feather...');
    try {
      await _startScan();
      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen(
            (results) async {
          for (ScanResult r in results) {
            String deviceName = (r.device.platformName.isNotEmpty
                ? r.device.platformName
                : r.advertisementData.advName)
                .toLowerCase();
            bool hasService = r.advertisementData.serviceUuids.any((guid) =>
            guid.toString().toLowerCase() == serviceUUID.toLowerCase());
            if (deviceName.contains('adafruit') ||
                deviceName.contains('feather') ||
                hasService) {
              await _stopScan();
              _device = r.device;
              _setConnectionStatus('Connecting to ${_device!.platformName}...');
              await _connect(_device!);
              break;
            }
          }
        },
        onError: (e) {
          _logger.e('Scan error: $e');
          _setConnectionStatus('Scan failed: $e');
        },
      );

      await Future.delayed(const Duration(seconds: 10));
      if (!_isConnected && mounted) {
        await _stopScan();
        _setConnectionStatus('Device not found');
        _showMessageDialog(context, 'Connection Error', 'Adafruit-Feather not found');
      }
    } catch (e) {
      _logger.e('Scan failed: $e');
      _setConnectionStatus('Scan failed: $e');
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 20));
      await device.requestMtu(517);
      _logger.i('Requested MTU of 517 bytes');
      int mtu = await device.mtu.first;
      _logger.i('Negotiated MTU: $mtu bytes');
      _device = device;
      _logger.i('Connected to ${device.platformName}');

      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen(
            (state) {
          _logger.d('Device connection state changed: $state');
          if (state == BluetoothConnectionState.disconnected && _isConnected) {
            _logger.w('Device disconnected unexpectedly');
            if (mounted) {
              setState(() {
                _isConnected = false;
                _connectionStatus = 'Disconnected';
                _deviceTime = 'Not available';
                _characteristicSubscription?.cancel();
                _characteristicSubscription = null;
                _uartTx = null;
                _uartRx = null;
              });
              _showMessageDialog(context, 'Connection Lost', 'Device disconnected unexpectedly');
            }
          } else if (state == BluetoothConnectionState.connected && !_isConnected) {
            _logger.i('Device reconnected, updating state');
            if (mounted) {
              setState(() {
                _isConnected = true;
                _connectionStatus = 'Connection established';
              });
            }
          }
        },
        onError: (e) {
          _logger.e('Connection state error: $e');
        },
      );

      List<BluetoothService> services = await device.discoverServices();
      BluetoothService? uartService;
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
          uartService = service;
          break;
        }
      }

      if (uartService == null) {
        _logger.e('UART service not found');
        await device.disconnect();
        _setConnectionStatus('UART service not found');
        return;
      }

      for (var characteristic in uartService.characteristics) {
        if (characteristic.uuid.toString().toLowerCase() == txUUID) {
          _uartTx = characteristic;
        } else if (characteristic.uuid.toString().toLowerCase() == rxUUID) {
          _uartRx = characteristic;
        }
      }

      if (_uartTx == null || _uartRx == null) {
        _logger.e('Required characteristics not found');
        await device.disconnect();
        _setConnectionStatus('RX/TX characteristic not found');
        return;
      }

      await _uartRx!.setNotifyValue(true);
      _characteristicSubscription = _uartRx!.lastValueStream.listen(
            (value) {
          if (value.isNotEmpty) {
            try {
              String data = utf8.decode(value, allowMalformed: true).trim();
              if (data.isNotEmpty) {
                _logger.d('Raw data received: $data');
                _parseReceivedData(data);
              }
            } catch (e) {
              _logger.e('Error decoding data: $e');
            }
          }
        },
        onError: (e) {
          _logger.e('Characteristic subscription error: $e');
        },
      );

      _isConnected = true;
      _setConnectionStatus('Connection established');

      await _syncTime();
    } catch (e) {
      _isConnected = false;
      _setConnectionStatus('Connection failed: $e');
      _logger.e('Connection failed: $e');
      rethrow;
    }
  }

  Future<void> _disconnectDevice() async {
    try {
      if (_device == null) {
        _logger.w('No device to disconnect');
        if (mounted) {
          setState(() {
            _isConnected = false;
            _connectionStatus = 'Disconnected';
            _device = null;
            _uartTx = null;
            _uartRx = null;
            _deviceTime = 'Not available';
            _characteristicSubscription?.cancel();
            _characteristicSubscription = null;
          });
          _showMessageDialog(context, 'Disconnect', 'No device is connected');
        }
        return;
      }

      final connectionState = await _device!.connectionState.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _logger.w('Connection state check timed out, assuming disconnected');
          return BluetoothConnectionState.disconnected;
        },
      );
      _logger.d('Device connection state: $connectionState, isConnected: $_isConnected');

      if (connectionState == BluetoothConnectionState.disconnected) {
        _logger.i('Device already disconnected, updating state');
        if (mounted) {
          setState(() {
            _isConnected = false;
            _connectionStatus = 'Disconnected';
            _device = null;
            _uartTx = null;
            _uartRx = null;
            _deviceTime = 'Not available';
            _characteristicSubscription?.cancel();
            _characteristicSubscription = null;
          });
          _showMessageDialog(context, 'Disconnect', 'Device was already disconnected');
        }
        return;
      }

      await _characteristicSubscription?.cancel();
      _characteristicSubscription = null;
      if (_uartRx != null) {
        try {
          await _uartRx!.setNotifyValue(false);
        } catch (e) {
          _logger.w('Failed to disable notifications: $e');
        }
      }
      await _device!.disconnect();
      _logger.i('Disconnected from ${_device!.platformName}');
      if (mounted) {
        setState(() {
          _device = null;
          _uartTx = null;
          _uartRx = null;
          _isConnected = false;
          _connectionStatus = 'Disconnected';
          _deviceTime = 'Not available';
        });
        _showMessageDialog(context, 'Disconnected', 'Disconnected from device');
      }
    } catch (e) {
      _logger.e('Failed to disconnect: $e');
      if (mounted) {
        setState(() {
          _isConnected = false;
          _connectionStatus = 'Disconnected';
          _device = null;
          _uartTx = null;
          _uartRx = null;
          _deviceTime = 'Not available';
          _characteristicSubscription?.cancel();
          _characteristicSubscription = null;
        });
        _showMessageDialog(context, 'Disconnect Error', 'Failed to disconnect, device state reset: $e');
      }
    }
  }

  Future<void> _syncTime() async {
    if (!_isConnected || _uartTx == null) {
      _logger.w('Cannot sync time: Not connected or TX unavailable');
      _showMessageDialog(context, 'Sync Error', 'Please connect to the device first');
      return;
    }
    final offsetHours = int.parse(_utcOffset.replaceFirst('+', ''));
    final offsetSeconds = offsetHours * 3600;
    final now = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + offsetSeconds;
    await _writeCommand('SYNC:$now');
    _logger.i('Sent SYNC:$now with UTC offset $_utcOffset');
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      _showMessageDialog(context, 'Time Synchronized', 'Device time synchronized to $now with UTC offset $_utcOffset');
    }
  }

  Future<bool> _writeCommand(String command) async {
    if (!_isConnected || _uartTx == null) {
      _logger.w('Cannot write: Not connected or TX unavailable');
      return false;
    }
    try {
      await _uartTx!.write(utf8.encode('$command\n'));
      _logger.i('Wrote command: $command');
      return true;
    } catch (e) {
      _logger.e('Failed to write command: $e');
      return false;
    }
  }

  Future<void> _readDeviceTime() async {
    if (!_isConnected || _uartTx == null) {
      _logger.w('Cannot read device time: Not connected or TX unavailable');
      _showMessageDialog(context, 'Device Time Error', 'Please connect to the device first');
      return;
    }
    try {
      setState(() {
        _deviceTime = 'Reading...';
      });
      bool success = await _writeCommand('GET_TIME');
      if (!success) {
        setState(() {
          _deviceTime = 'Not available';
        });
        _showMessageDialog(context, 'Device Time Error', 'Failed to send GET_TIME command');
      }
      await Future.delayed(const Duration(seconds: 2));
      if (_deviceTime == 'Reading...') {
        setState(() {
          _deviceTime = 'Not available';
        });
        _showMessageDialog(context, 'Device Time Error', 'No response from device');
      }
    } catch (e) {
      _logger.e('Failed to read device time: $e');
      setState(() {
        _deviceTime = 'Not available';
      });
      _showMessageDialog(context, 'Device Time Error', 'Failed to read device time: $e');
    }
  }

  Future<void> _startLiveData() async {
    if (!_isConnected || _uartTx == null) {
      _logger.w('Cannot start live data: Not connected or TX unavailable');
      return;
    }
    await _writeCommand('START_LIVE_DATA');
    _logger.i('Sent START_LIVE_DATA');
  }

  Future<void> _stopLiveData() async {
    if (!_isConnected || _uartTx == null) {
      _logger.w('Cannot stop live data: Not connected or TX unavailable');
      return;
    }
    await _writeCommand('STOP_LIVE_DATA');
    _logger.i('Sent STOP_LIVE_DATA');
  }

  Future<void> _navigateToLiveCharts() async {
    await _startLiveData();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveChartsScreen(
          liveDataStream: _liveDataController.stream,
        ),
      ),
    );
    await _stopLiveData();
  }

  Future<void> _setManualTimestamp(BuildContext dialogContext) async {
    if (!mounted) {
      _logger.w('Cannot show date picker: HomeScreen widget not mounted');
      return;
    }

    _logger.i('Starting setManualTimestamp');
    final now = DateTime.now();
    final firstDate = DateTime(2020);
    final lastDate = now;

    DateTime initialDate;
    if (_lastTimestamp == 0) {
      initialDate = lastDate;
      _logger.d('No last timestamp, setting initialDate to lastDate: $lastDate');
    } else {
      final timestampDate = DateTime.fromMillisecondsSinceEpoch(_lastTimestamp * 1000);
      if (timestampDate.isAfter(lastDate) || timestampDate.isBefore(firstDate)) {
        _logger.w('Invalid lastTimestamp: $_lastTimestamp, results in $timestampDate, setting initialDate to lastDate: $lastDate');
        initialDate = lastDate;
      } else {
        initialDate = timestampDate;
        _logger.d('Valid lastTimestamp: $_lastTimestamp, setting initialDate to $initialDate');
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
        _showMessageDialog(context, 'Timestamp Error', 'Failed to open date picker: $e');
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
        initialTime: _lastTimestamp == 0
            ? TimeOfDay.fromDateTime(now)
            : TimeOfDay.fromDateTime(
            DateTime.fromMillisecondsSinceEpoch(_lastTimestamp * 1000)),
      );
      _logger.d('Time picker result: $time');
    } catch (e) {
      _logger.e('Failed to show time picker: $e');
      if (mounted) {
        _showMessageDialog(context, 'Timestamp Error', 'Failed to open time picker: $e');
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

    final nowTruncated = DateTime(now.year, now.month, now.day, now.hour, now.minute);
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
        _showMessageDialog(context, 'Timestamp Error', 'Cannot set timestamp to future time');
      }
      return;
    }

    if (mounted) {
      setState(() {
        _lastTimestamp = selectedDateTime.millisecondsSinceEpoch ~/ 1000;
      });
      _logger.i('Set lastTimestamp to: $_lastTimestamp');
      await _saveLastTimestamp();
      _showMessageDialog(
        context,
        'Timestamp Updated',
        'Last timestamp set to ${selectedDateTime.toString().substring(0, 16)}',
      );
      _logger.i('Completed setManualTimestamp: $_lastTimestamp');
    }
  }

  Future<void> _parseReceivedData(String data) async {
    _dataBuffer += data;
    _logger.d('Buffer updated: $_dataBuffer, isFullRetrieval: $_isFullRetrieval');

    while (_dataBuffer.isNotEmpty) {
      if (_dataBuffer == 'OK') {
        _logger.i('Received OK');
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer == 'PONG') {
        _logger.i('Received PONG');
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer.startsWith('ERROR:')) {
        _logger.e('Error received: $_dataBuffer');
        _showMessageDialog(context, 'Device Error', 'Device error: $_dataBuffer');
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer.startsWith('TIME:')) {
        try {
          final timestamp = int.parse(_dataBuffer.split(':')[1].trim());
          final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
          setState(() {
            _deviceTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
          });
          _logger.i('Received device time: $_deviceTime');
          _showMessageDialog(context, 'Device Time', 'Device time: $_deviceTime');
        } catch (e) {
          _logger.e('Invalid TIME response: $_dataBuffer, Error: $e');
          setState(() {
            _deviceTime = 'Not available';
          });
          _showMessageDialog(context, 'Device Time Error', 'Invalid device time response');
        }
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer == 'SEND_START') {
        _logger.i('Received SEND_START');
        _isReceivingData = true;
        _pendingRow = null;
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer == 'SEND_END' && _isReceivingData) {
        _logger.i('Received SEND_END');
        _isReceivingData = false;
        if (_pendingRow != null) {
          _processCsvRow(_pendingRow!, isFullRetrieval: _isFullRetrieval);
          _pendingRow = null;
        }
        _dataBuffer = '';
        _isFullRetrieval = false;
        continue;
      } else if (_dataBuffer == 'END_OF_DATA') {
        _logger.i('Received END_OF_DATA');
        _isReceivingData = false;
        if (_pendingRow != null) {
          _processCsvRow(_pendingRow!, isFullRetrieval: _isFullRetrieval);
          _pendingRow = null;
        }
        await _saveCsvData();
        setState(() {
          _lastTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        });
        await _saveLastTimestamp();
        _dataBuffer = '';
        _isFullRetrieval = false;
        continue;
      }

      if (_isReceivingData) {
        int newlineIndex = _dataBuffer.indexOf('\n');
        if (newlineIndex == -1 && _dataBuffer.contains(',')) {
          List<String> fields = _dataBuffer.split(',');
          if (fields.length >= 4) {
            _pendingRow = _dataBuffer;
            _processCsvRow(_pendingRow!, isFullRetrieval: _isFullRetrieval);
            _pendingRow = null;
            _dataBuffer = '';
          } else {
            _pendingRow = _dataBuffer;
            break;
          }
        } else if (newlineIndex != -1) {
          String line = _dataBuffer.substring(0, newlineIndex).trim();
          _dataBuffer = _dataBuffer.substring(newlineIndex + 1);
          if (line.isNotEmpty) {
            _pendingRow = line;
            _processCsvRow(_pendingRow!, isFullRetrieval: _isFullRetrieval);
            _pendingRow = null;
          }
          continue;
        } else {
          _pendingRow = _dataBuffer;
          break;
        }
      } else {
        _logger.w('Unexpected data, not in SEND_START/SEND_END block: $_dataBuffer');
        _dataBuffer = '';
      }
    }
  }

  void _processCsvRow(String row, {bool isFullRetrieval = false}) {
    _logger.d('Processing row: $row, isFullRetrieval: $isFullRetrieval');
    List<String> fields = row.split(',');
    if (fields.length == 4) {
      try {
        int timestamp = int.parse(fields[0]);
        double flowRate = double.parse(fields[1]);
        double batteryVoltage = double.parse(fields[2]);
        double tapOnDuration = double.parse(fields[3]);

        setState(() {
          _csvData.add([timestamp, flowRate, batteryVoltage, tapOnDuration]);
        });
        _liveDataController.add([timestamp, flowRate, batteryVoltage, tapOnDuration]);
        _logger.i('Parsed and added row: $fields, updated lastTimestamp to $_lastTimestamp');
      } catch (e) {
        _logger.e('Error parsing CSV row: $row, Error: $e');
      }
    } else {
      _logger.w('Invalid row format, expected 4 fields, got ${fields.length}: $row');
    }
  }

  Map<String, dynamic> _processCsvData() {
    int originalCount = _csvData.length;

    final now = DateTime.now();
    final sixMonthsAgo = now.subtract(const Duration(days: 182));
    final currentTimestamp = now.millisecondsSinceEpoch ~/ 1000;
    final sixMonthsAgoTimestamp = sixMonthsAgo.millisecondsSinceEpoch ~/ 1000;

    _csvData = _csvData.where((row) {
      int timestamp = row[0] as int;
      return timestamp >= sixMonthsAgoTimestamp && timestamp <= currentTimestamp;
    }).toList();

    int filteredCount = originalCount - _csvData.length;
    _logger.i('Filtered $filteredCount rows (older than 6 months or future timestamps)');

    final uniqueRows = <String, List<dynamic>>{};
    for (var row in _csvData) {
      uniqueRows[row.join(',')] = row;
    }
    _csvData = uniqueRows.values.toList();
    int duplicateCount = originalCount - filteredCount - _csvData.length;
    _logger.i('Removed $duplicateCount duplicate rows, unique rows: ${_csvData.length}');

    _csvData.sort((a, b) => (a[0] as int).compareTo(b[0] as int));
    _logger.i('Sorted ${_csvData.length} rows by timestamp');

    return {
      'duplicateCount': duplicateCount,
      'filteredCount': filteredCount,
      'rowCount': _csvData.length,
    };
  }

  Future<void> _saveCsvData() async {
    try {
      const documentsPath = '/storage/emulated/0/Documents';
      final directory = Directory(documentsPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final file = File('$documentsPath/water_data.csv');

      final result = _processCsvData();

      final sink = file.openWrite();
      sink.write('timestamp,water_flow_rate,battery_voltage,tap_on_duration\n');
      for (var row in _csvData) {
        sink.write('${row.join(',')}\n');
      }
      await sink.flush();
      await sink.close();

      final fileSize = await file.length();
      final saveTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final fileSizeKB = (fileSize / 1024).toStringAsFixed(2);

      _logger.i(
          'Saved CSV file: '
              'Path: ${file.path}, '
              'Rows: ${result['rowCount']}, '
              'Size: $fileSizeKB KB ($fileSize bytes), '
              'Saved at: $saveTime, '
              'Duplicates removed: ${result['duplicateCount']}, '
              'Filtered rows: ${result['filteredCount']}'
      );

      if (mounted) {
        Navigator.of(context, rootNavigator: false).pop(); // Dismiss progress dialog
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
        Navigator.of(context, rootNavigator: false).pop(); // Dismiss progress dialog
        _showMessageDialog(context, 'CSV Error', 'Failed to save data: $e');
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

    try {
      const documentsPath = '/storage/emulated/0/Documents';
      final file = File('$documentsPath/water_data.csv');

      await _loadCsvData();

      if (!await file.exists() || _csvData.isEmpty) {
        _logger.i('No data to clean: File does not exist or is empty');
        return {
          'success': false,
          'message': 'No data available to clean',
        };
      }

      final result = _processCsvData();

      final sink = file.openWrite();
      sink.write('timestamp,water_flow_rate,battery_voltage,tap_on_duration\n');
      for (var row in _csvData) {
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

      _logger.i(
          'Cleaned CSV file: '
              'Path: ${file.path}, '
              'Rows: ${result['rowCount']}, '
              'Size: $fileSizeKB KB ($fileSize bytes), '
              'Saved at: $saveTime, '
              'Duplicates removed: ${result['duplicateCount']}, '
              'Filtered rows: ${result['filteredCount']}'
      );

      await _saveCsvSummary(summary);
      setState(() {
        _lastTimestamp = _csvData.isNotEmpty
            ? _csvData.map((row) => row[0] as int).reduce((a, b) => a > b ? a : b)
            : 0;
      });
      await _saveLastTimestamp();

      return summary;
    } catch (e) {
      _logger.e('Error cleaning CSV: $e');
      return {
        'success': false,
        'message': 'Failed to clean CSV: $e',
      };
    }
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

  Future<void> _showResultDialog(BuildContext context, bool success, String message) async {
    if (mounted) {
      Navigator.of(context, rootNavigator: false).pop(); // Dismiss progress dialog
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

  Future<int> _fetchData(String command, {bool isFullRetrieval = false}) async {
    if (!_isConnected || _uartTx == null || _uartRx == null) {
      _logger.w('Cannot retrieve data: Not connected or UART unavailable');
      if (mounted) {
        Navigator.of(context, rootNavigator: false).pop(); // Dismiss progress dialog if open
        _showMessageDialog(context, 'Data Retrieval Error', 'Please connect to the device first');
      }
      return _lastTimestamp;
    }
    setState(() {
      _isFullRetrieval = isFullRetrieval;
    });
    _logger.i('Starting fetchData with command: $command, isFullRetrieval: $_isFullRetrieval');

    await _showProgressDialog(context);

    try {
      _dataBuffer = '';
      _isReceivingData = false;
      _pendingRow = null;
      int initialRowCount = _csvData.length;
      await _writeCommand(command);
      _logger.i('Sent command: $command');

      await Future.delayed(const Duration(seconds: 60));

      int newRows = _csvData.length - initialRowCount;
      String message;
      if (newRows > 0) {
        _logger.i('Received $newRows new rows, lastTimestamp updated to $_lastTimestamp');
        message = 'Successfully retrieved $newRows new rows.';
      } else {
        _logger.i('No new data received for command: $command');
        message = 'No new data available';
      }

      if (_csvData.isNotEmpty) {
        setState(() {
          _lastTimestamp = _csvData
              .map((row) => row[0] as int)
              .reduce((a, b) => a > b ? a : b);
        });
      }
      await _saveLastTimestamp();
      if (newRows > 0) {
        await _saveCsvData();
      }
      await _showResultDialog(context, true, message);
      return _lastTimestamp;
    } catch (e) {
      _logger.e('Failed to retrieve data: $e');
      await _showResultDialog(context, false, 'Failed to retrieve data: $e');
      return _lastTimestamp;
    }
  }

  Future<int> _retrieveData() async {
    _logger.i('Preparing to retrieve data with lastTimestamp: $_lastTimestamp');
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _logger.i('Current timestamp: $currentTimestamp');
    if (_lastTimestamp >= currentTimestamp - 5) {
      _logger.w('Warning: lastTimestamp ($_lastTimestamp) is close to current time ($currentTimestamp), possible overwrite');
    }

    if (_lastTimestamp == 0) {
      _logger.w('No valid timestamp found, retrieving all data');
      await _showMessageDialog(
        context,
        'Data Retrieval',
        'No previous data found. Retrieving all available data from device.',
      );
    }
    String command = 'GET_DATA since $_lastTimestamp';
    return await _fetchData(command);
  }

  Future<int> _retrieveAllData() async {
    _logger.i('Preparing to retrieve all data (GET_DATA since 0)');
    await _showMessageDialog(context, 'Data Retrieval', 'Retrieving all data from device...');
    String command = 'GET_DATA since 0';
    return await _fetchData(command, isFullRetrieval: true);
  }

  Future<void> _clearCsvData() async {
    bool confirmed = await _showConfirmClearDialog(context);
    if (!confirmed) {
      _logger.i('CSV clearing cancelled by user');
      return;
    }

    try {
      final file = File('/storage/emulated/0/Documents/water_data.csv');
      if (await file.exists()) {
        await file.delete();
        setState(() {
          _csvData = [];
          _lastTimestamp = 0;
        });
        await _saveLastTimestamp();
        await _saveCsvSummary({
          'success': false,
          'message': 'CSV file cleared',
        });
        _logger.i('Cleared CSV data, reset lastTimestamp to 0');
        _showMessageDialog(context, 'Data Cleared', 'CSV data cleared successfully');
      } else {
        _logger.i('No CSV file to clear');
        _showMessageDialog(context, 'Data Cleared', 'No CSV file to clear');
      }
    } catch (e) {
      _logger.e('Error clearing CSV: $e');
      _showMessageDialog(context, 'CSV Error', 'Failed to clear CSV: $e');
    }
  }

  @override
  void dispose() {
    _characteristicSubscription?.cancel();
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _liveDataController.close();
    _device?.disconnect();
    FlutterBluePlus.stopScan();
    _stopLiveData();
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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                  'Connection Status: ',
                  style: TextStyle(color: Colors.white),
                ),
                Text(
                  _connectionStatus,
                  style: TextStyle(
                    color: _isConnected ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
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
                    csvData: _csvData,
                    lastTimestamp: _lastTimestamp,
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
                MaterialPageRoute(builder: (_) => ReportsScreen(_csvData)),
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
                    connectionStatus: _connectionStatus,
                    isConnected: _isConnected,
                    utcOffset: _utcOffset,
                    deviceTime: _deviceTime,
                    onConnectToDevice: _connectToDevice,
                    onDisconnectDevice: _disconnectDevice,
                    onSyncTime: _syncTime,
                    onReadDeviceTime: _readDeviceTime,
                    onUpdateUtcOffset: (value) {
                      setState(() {
                        _utcOffset = value;
                      });
                      _logger.i('UTC offset changed to: $_utcOffset');
                    },
                    onUpdateDeviceTime: (value) {
                      setState(() {
                        _deviceTime = value;
                      });
                      _logger.i('Device time updated to: $_deviceTime');
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}