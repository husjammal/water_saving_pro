import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import 'reports_screen.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Logger _logger = Logger();
  String _connectionStatus = 'Disconnected';
  bool _isConnected = false;
  List<List<dynamic>> _csvData = [];
  int _lastTimestamp = 0;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _uartTx;
  BluetoothCharacteristic? _uartRx;
  StreamSubscription<List<int>>? _characteristicSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  String _dataBuffer = '';
  bool _isReceivingData = false;
  String? _pendingRow;

  // Nordic UART Service UUIDs
  final String serviceUUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  final String txUUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"; // Write
  final String rxUUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"; // Read/Notify

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadCsvData(); // Load existing CSV data
  }

  Future<void> _requestPermissions() async {
    try {
      await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
        Permission.storage,
        Permission.manageExternalStorage, // Required for Documents folder
      ].request();
      _logger.i('Permissions requested');
      _connectToDevice(); // Start connection after permissions
    } catch (e) {
      _logger.e('Permission request failed: $e');
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Permission request failed: $e')),
      );
    }
  }

  Future<void> _loadCsvData() async {
    try {
      final directory = await getExternalStorageDirectory();
      final documentsPath = '/storage/emulated/0/Documents';
      final file = File('$documentsPath/water_data.csv');
      if (await file.exists()) {
        final csvString = await file.readAsString();
        final csvList = const CsvToListConverter().convert(csvString, eol: '\n');
        if (csvList.length > 1) {
          _csvData = csvList.skip(1).toList();
          _lastTimestamp = _csvData
              .map((row) => row[0] as int)
              .reduce((a, b) => a > b ? a : b);
          _logger.i('Loaded ${_csvData.length} records from CSV, last timestamp: $_lastTimestamp');
        } else {
          _logger.i('CSV file exists but contains no data rows');
          _lastTimestamp = 0;
        }
      } else {
        _logger.i('CSV file does not exist, initializing with last timestamp: 0');
        _lastTimestamp = 0;
      }
    } catch (e) {
      _logger.e('Failed to load CSV: $e');
      _lastTimestamp = 0;
    }
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
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(status)),
        );
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
            bool hasService = r.advertisementData.serviceUuids
                .any((guid) => guid.toString().toLowerCase() == serviceUUID.toLowerCase());
            if (deviceName.contains('adafruit') || deviceName.contains('feather') || hasService) {
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
        _scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Adafruit-Feather not found')),
        );
      }
    } catch (e) {
      _logger.e('Scan failed: $e');
      _setConnectionStatus('Scan failed: $e');
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 20));
      _device = device;
      _logger.i('Connected to ${device.platformName}');

      List<BluetoothService> services = await device.discoverServices();
      BluetoothService? uartService;
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUUID) {
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

      for (var char in uartService.characteristics) {
        if (char.uuid.toString().toLowerCase() == txUUID) {
          _uartTx = char;
        } else if (char.uuid.toString().toLowerCase() == rxUUID) {
          _uartRx = char;
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

      // Perform time sync
      await _syncTime();
    } catch (e) {
      _isConnected = false;
      _setConnectionStatus('Connection failed: $e');
      _logger.e('Connection failed: $e');
      rethrow;
    }
  }

  Future<void> _syncTime() async {
    if (!_isConnected || _uartTx == null) {
      _logger.w('Cannot sync time: Not connected or TX unavailable');
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Please connect to the device first')),
      );
      return;
    }

    // Send SYNC with retries
    bool syncSuccess = false;
    for (int attempt = 1; attempt <= 3; attempt++) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000; // Unix seconds
      await _writeCommand('SYNC:$now');
      _logger.i('Sent SYNC:$now (attempt $attempt)');
      await Future.delayed(const Duration(seconds: 2)); // Wait for response
      if (_dataBuffer.contains('OK')) {
        syncSuccess = true;
        break;
      }
    }

    if (!syncSuccess) {
      _logger.w('SYNC failed after 3 attempts');
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Failed to sync time with device')),
      );
    } else {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Time synchronized successfully')),
      );
      // Send PING to test responsiveness
      await _writeCommand('PING');
      _logger.i('Sent PING');
      // Request data after successful sync
      await _retrieveData();
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

  void _parseReceivedData(String data) {
    // Append incoming data to buffer
    _dataBuffer += data;
    _logger.d('Buffer updated: $_dataBuffer');

    // Process buffer while it contains complete messages or rows
    while (_dataBuffer.isNotEmpty) {
      // Handle control messages
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
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Device error: $_dataBuffer')),
        );
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
        // Process any remaining pending row
        if (_pendingRow != null) {
          _processCsvRow(_pendingRow!);
          _pendingRow = null;
        }
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer == 'END_OF_DATA') {
        _logger.i('Received END_OF_DATA');
        _isReceivingData = false;
        // Process any remaining pending row
        if (_pendingRow != null) {
          _processCsvRow(_pendingRow!);
          _pendingRow = null;
        }
        _saveCsvData();
        _dataBuffer = '';
        continue;
      }

      // Handle CSV data during SEND_START/SEND_END
      if (_isReceivingData) {
        // Look for a complete row (contains at least one comma and likely 5 fields)
        int newlineIndex = _dataBuffer.indexOf('\n');
        if (newlineIndex == -1 && _dataBuffer.contains(',')) {
          // No newline, but contains commas; wait for more data unless it's a full row
          List<String> fields = _dataBuffer.split(',');
          if (fields.length >= 5) {
            // Assume complete row if 5 or more fields
            _pendingRow = _dataBuffer;
            _processCsvRow(_pendingRow!);
            _pendingRow = null;
            _dataBuffer = '';
          } else {
            // Partial row, wait for more data
            _pendingRow = _dataBuffer;
            break;
          }
        } else if (newlineIndex != -1) {
          // Found a newline, process the line
          String line = _dataBuffer.substring(0, newlineIndex).trim();
          _dataBuffer = _dataBuffer.substring(newlineIndex + 1);
          if (line.isNotEmpty) {
            _pendingRow = line;
            _processCsvRow(_pendingRow!);
            _pendingRow = null;
          }
          continue;
        } else {
          // No newline or commas, wait for more data
          _pendingRow = _dataBuffer;
          break;
        }
      } else {
        // Unexpected data outside SEND_START/SEND_END
        _logger.w('Unexpected data, not in SEND_START/SEND_END block: $_dataBuffer');
        _dataBuffer = '';
      }
    }
  }

  void _processCsvRow(String row) {
    List<String> fields = row.split(',');
    if (fields.length == 5) {
      try {
        int timestamp = int.parse(fields[0]);
        double flowRate = double.parse(fields[1]);
        double batteryVoltage = double.parse(fields[2]);
        double tapOnDuration = double.parse(fields[3]);
        int syncFlag = int.parse(fields[4]);

        // Add to _csvData if timestamp is newer
        if (timestamp > _lastTimestamp) {
          setState(() {
            _csvData.add([timestamp, flowRate, batteryVoltage, tapOnDuration, syncFlag]);
            _lastTimestamp = timestamp;
          });
          _logger.i('Parsed and added row: $fields');
        } else {
          _logger.d('Skipped old or duplicate timestamp: $timestamp');
        }
      } catch (e) {
        _logger.e('Error parsing CSV row: $row, Error: $e');
      }
    } else {
      _logger.w('Invalid row format, expected 5 fields, got ${fields.length}: $row');
    }
  }

  Future<void> _saveCsvData() async {
    try {
      final documentsPath = '/storage/emulated/0/Documents';
      final directory = Directory(documentsPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final file = File('$documentsPath/water_data.csv');
      String csvContent = 'timestamp,water_flow_rate,battery_voltage,tap_on_duration,sync_flag\n';
      for (var row in _csvData) {
        csvContent += row.join(',') + '\n';
      }
      await file.writeAsString(csvContent);
      _logger.i('Saved CSV file to: ${file.path}');
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Data saved to ${file.path}')),
      );
    } catch (e) {
      _logger.e('Error saving CSV: $e');
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Failed to save data: $e')),
      );
    }
  }

  Future<void> _retrieveData() async {
    if (!_isConnected || _uartTx == null || _uartRx == null) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Please connect to the device first')),
      );
      return;
    }

    _scaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Downloading data...'),
            SizedBox(height: 8),
            LinearProgressIndicator(),
          ],
        ),
        duration: Duration(seconds: 30),
      ),
    );

    try {
      // Clear buffer and reset state before retrieving data
      _dataBuffer = '';
      _isReceivingData = false;
      _pendingRow = null;

      // Send GET_DATA with the last timestamp
      int initialRowCount = _csvData.length;
      await _writeCommand('GET_DATA since $_lastTimestamp');
      _logger.i('Sent GET_DATA since $_lastTimestamp');

      // Wait for data with a timeout
      await Future.delayed(const Duration(seconds: 15));

      int newRows = _csvData.length - initialRowCount;
      if (newRows > 0) {
        _logger.i('Received $newRows new rows');
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Retrieved $newRows new data rows')),
        );
      } else {
        _logger.i('No new data received');
        _scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('No new data available')),
        );
      }

      // Save any new data to CSV
      if (newRows > 0) {
        await _saveCsvData();
      }
    } catch (e) {
      _logger.e('Failed to retrieve data: $e');
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Failed to retrieve data: $e')),
      );
    }
  }

  @override
  void dispose() {
    _characteristicSubscription?.cancel();
    _scanSubscription?.cancel();
    _device?.disconnect();
    FlutterBluePlus.stopScan();
    _logger.i('HomeScreen disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldMessengerKey,
      appBar: AppBar(title: const Text('Water Monitor')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Connection Status: $_connectionStatus'),
            ElevatedButton(
              onPressed: _connectToDevice,
              child: const Text('Connect to Device'),
            ),
            ElevatedButton(
              onPressed: _syncTime,
              child: const Text('Sync Time'),
            ),
            ElevatedButton(
              onPressed: _retrieveData,
              child: const Text('Retrieve Data'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ReportsScreen(_csvData)),
              ),
              child: const Text('View Reports'),
            ),
          ],
        ),
      ),
    );
  }
}