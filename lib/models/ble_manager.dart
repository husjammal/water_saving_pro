import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BleManager {
  final Logger _logger = Logger();
  String _connectionStatus = 'Disconnected';
  bool _isConnected = false;
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

  final StreamController<String> _connectionStatusController =
  StreamController<String>.broadcast();
  final StreamController<String> _deviceTimeController =
  StreamController<String>.broadcast();
  final StreamController<List<ScanResult>> _scanResultsController =
  StreamController<List<ScanResult>>.broadcast();
  final StreamController<bool> _isScanningController =
  StreamController<bool>.broadcast();

  Stream<String> get connectionStatusStream => _connectionStatusController.stream;
  Stream<String> get deviceTimeStream => _deviceTimeController.stream;
  Stream<List<ScanResult>> get scanResultsStream => _scanResultsController.stream;
  Stream<bool> get isScanningStream => _isScanningController.stream;
  Stream<List<dynamic>> get liveDataStream => _liveDataController.stream;

  String get connectionStatus => _connectionStatus;
  bool get isConnected => _isConnected;
  String get deviceTime => _deviceTime;

  void _setConnectionStatus(String status) {
    _connectionStatus = status;
    _isConnected = status == 'Connection established';
    _connectionStatusController.add(status);
    _logger.i('Connection status: $status');
  }

  void _setDeviceTime(String time) {
    _deviceTime = time;
    _deviceTimeController.add(time);
    _logger.i('Device time updated: $time');
  }

  Future<void> startScan() async {
    try {
      if (await FlutterBluePlus.isScanning.first) {
        await FlutterBluePlus.stopScan();
      }
      _scanResultsController.add([]); // Clear previous results
      _isScanningController.add(true);
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen(
            (results) {
          List<ScanResult> filteredResults = results.where((r) {
            String deviceName = (r.device.platformName.isNotEmpty
                ? r.device.platformName
                : r.advertisementData.advName)
                .toLowerCase();
            bool hasService = r.advertisementData.serviceUuids.any((guid) =>
            guid.toString().toLowerCase() == serviceUUID.toLowerCase());
            return deviceName.contains('adafruit') ||
                deviceName.contains('feather') ||
                hasService;
          }).toList();
          _scanResultsController.add(filteredResults);
          if (filteredResults.isNotEmpty) {
            stopScan(); // Stop scan if at least one device is found
          }
        },
        onError: (e) {
          _logger.e('Scan error: $e');
          _setConnectionStatus('Scan failed: $e');
          _isScanningController.add(false);
        },
      );
      _logger.i('Bluetooth scan started');
    } catch (e) {
      _logger.e('Failed to start scan: $e');
      _setConnectionStatus('Scan failed: $e');
      _isScanningController.add(false);
      rethrow;
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _scanSubscription = null;
      _isScanningController.add(false);
      _logger.i('Bluetooth scan stopped');
    } catch (e) {
      _logger.e('Failed to stop scan: $e');
      _isScanningController.add(false);
      rethrow;
    }
  }

  Future<void> autoConnectToDevice() async {
    _setConnectionStatus('Scanning for Adafruit-Feather...');
    try {
      // Try to reconnect to last device first
      final prefs = await SharedPreferences.getInstance();
      final lastDeviceId = prefs.getString('last_device_id');
      final lastDeviceName = prefs.getString('last_device_name');
      if (lastDeviceId != null && lastDeviceName != null) {
        _setConnectionStatus('Attempting to reconnect to $lastDeviceName...');
        final devices = FlutterBluePlus.connectedDevices;
        for (var device in devices) {
          if (device.remoteId.toString() == lastDeviceId) {
            _device = device;
            await connect(device);
            return;
          }
        }
        // If not connected, scan for the last device
        await startScan();
        _scanSubscription?.cancel();
        _scanSubscription = FlutterBluePlus.scanResults.listen(
              (results) async {
            for (ScanResult r in results) {
              if (r.device.remoteId.toString() == lastDeviceId) {
                await stopScan();
                _device = r.device;
                _setConnectionStatus('Connecting to $lastDeviceName...');
                await connect(_device!);
                return;
              }
            }
          },
          onError: (e) {
            _logger.e('Scan error: $e');
            _setConnectionStatus('Scan failed: $e');
          },
        );
        await Future.delayed(const Duration(seconds: 5));
        if (_isConnected) return;
      }

      // Fallback to scanning for any compatible device
      await startScan();
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
              await stopScan();
              _device = r.device;
              _setConnectionStatus('Connecting to ${_device!.platformName}...');
              await connect(_device!);
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
      if (!_isConnected) {
        await stopScan();
        _setConnectionStatus('Device not found');
      }
    } catch (e) {
      _logger.e('Scan failed: $e');
      _setConnectionStatus('Scan failed: $e');
    }
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    _setConnectionStatus('Connecting to ${device.platformName}...');
    try {
      await stopScan();
      await connect(device);
    } catch (e) {
      _logger.e('Connection failed: $e');
      _setConnectionStatus('Connection failed: $e');
      rethrow;
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 20));
      await device.requestMtu(517);
      _logger.i('Requested MTU of 517 bytes');
      int mtu = await device.mtu.first;
      _logger.i('Negotiated MTU: $mtu bytes');
      _device = device;
      _logger.i('Connected to ${device.platformName}');

      // Persist the connected device
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_device_id', device.remoteId.toString());
      await prefs.setString('last_device_name', device.platformName.isNotEmpty ? device.platformName : 'Unnamed Device');
      _logger.i('Persisted last connected device: ${device.remoteId}, ${device.platformName}');

      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen(
            (state) {
          _logger.d('Device connection state changed: $state');
          if (state == BluetoothConnectionState.disconnected && _isConnected) {
            _logger.w('Device disconnected unexpectedly');
            _setConnectionStatus('Disconnected');
            _setDeviceTime('Not available');
            _characteristicSubscription?.cancel();
            _characteristicSubscription = null;
            _uartTx = null;
            _uartRx = null;
          } else if (state == BluetoothConnectionState.connected && !_isConnected) {
            _logger.i('Device reconnected');
            _setConnectionStatus('Connection established');
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
                parseReceivedData(data);
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
      await syncTime('+0');
    } catch (e) {
      _isConnected = false;
      _setConnectionStatus('Connection failed: $e');
      _logger.e('Connection failed: $e');
      rethrow;
    }
  }

  Future<void> disconnectDevice() async {
    try {
      if (_device == null) {
        _logger.w('No device to disconnect');
        _isConnected = false;
        _setConnectionStatus('Disconnected');
        _setDeviceTime('Not available');
        _characteristicSubscription?.cancel();
        _characteristicSubscription = null;
        _uartTx = null;
        _uartRx = null;
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
        _logger.i('Device already disconnected');
        _isConnected = false;
        _setConnectionStatus('Disconnected');
        _setDeviceTime('Not available');
        _characteristicSubscription?.cancel();
        _characteristicSubscription = null;
        _uartTx = null;
        _uartRx = null;
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
      _device = null;
      _uartTx = null;
      _uartRx = null;
      _isConnected = false;
      _setConnectionStatus('Disconnected');
      _setDeviceTime('Not available');
    } catch (e) {
      _logger.e('Failed to disconnect: $e');
      _isConnected = false;
      _setConnectionStatus('Disconnected');
      _setDeviceTime('Not available');
      _device = null;
      _uartTx = null;
      _uartRx = null;
      _characteristicSubscription?.cancel();
      _characteristicSubscription = null;
    }
  }

  Future<bool> writeCommand(String command) async {
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

  Future<void> syncTime(String utcOffset) async {
    if (!_isConnected || _uartTx == null) {
      _logger.w('Cannot sync time: Not connected or TX unavailable');
      return;
    }
    final offsetHours = int.parse(utcOffset.replaceFirst('+', ''));
    final offsetSeconds = offsetHours * 3600;
    final now = (DateTime.now().millisecondsSinceEpoch ~/ 1000) + offsetSeconds;
    await writeCommand('SYNC:$now');
    _logger.i('Sent SYNC:$now with UTC offset $utcOffset');
  }

  Future<void> readDeviceTime() async {
    if (!_isConnected || _uartTx == null) {
      _logger.w('Cannot read device time: Not connected or TX unavailable');
      return;
    }
    try {
      _setDeviceTime('Reading...');
      bool success = await writeCommand('GET_TIME');
      if (!success) {
        _setDeviceTime('Not available');
      }
      await Future.delayed(const Duration(seconds: 2));
      if (_deviceTime == 'Reading...') {
        _setDeviceTime('Not available');
      }
    } catch (e) {
      _logger.e('Failed to read device time: $e');
      _setDeviceTime('Not available');
    }
  }

  Future<void> startLiveData() async {
    if (!_isConnected || _uartTx == null) {
      _logger.w('Cannot start live data: Not connected or TX unavailable');
      return;
    }
    await writeCommand('START_LIVE_DATA');
    _logger.i('Sent START_LIVE_DATA');
  }

  Future<void> stopLiveData() async {
    if (!_isConnected || _uartTx == null) {
      _logger.w('Cannot stop live data: Not connected or TX unavailable');
      return;
    }
    await writeCommand('STOP_LIVE_DATA');
    _logger.i('Sent STOP_LIVE_DATA');
  }

  void parseReceivedData(String data) {
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
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer.startsWith('TIME:')) {
        try {
          final timestamp = int.parse(_dataBuffer.split(':')[1].trim());
          final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
          _setDeviceTime(DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime));
        } catch (e) {
          _logger.e('Invalid TIME response: $_dataBuffer, Error: $e');
          _setDeviceTime('Not available');
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
          processCsvRow(_pendingRow!, isFullRetrieval: _isFullRetrieval);
          _pendingRow = null;
        }
        _dataBuffer = '';
        _isFullRetrieval = false;
        if (_fetchCompleter != null && !_fetchCompleter!.isCompleted) {
          _fetchCompleter!.complete();
        }
        continue;
      } else if (_dataBuffer == 'END_OF_DATA') {
        _logger.i('Received END_OF_DATA');
        _isReceivingData = false;
        if (_pendingRow != null) {
          processCsvRow(_pendingRow!, isFullRetrieval: _isFullRetrieval);
          _pendingRow = null;
        }
        _dataBuffer = '';
        _isFullRetrieval = false;
        if (_fetchCompleter != null && !_fetchCompleter!.isCompleted) {
          _fetchCompleter!.complete();
        }
        continue;
      }

      if (_isReceivingData) {
        int newlineIndex = _dataBuffer.indexOf('\n');
        if (newlineIndex == -1 && _dataBuffer.contains(',')) {
          List<String> fields = _dataBuffer.split(',');
          if (fields.length >= 4) {
            _pendingRow = _dataBuffer;
            processCsvRow(_pendingRow!, isFullRetrieval: _isFullRetrieval);
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
            processCsvRow(_pendingRow!, isFullRetrieval: _isFullRetrieval);
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

  void processCsvRow(String row, {bool isFullRetrieval = false}) {
    _logger.d('Processing row: $row, isFullRetrieval: $isFullRetrieval');
    List<String> fields = row.split(',');
    if (fields.length == 4) {
      try {
        int timestamp = int.parse(fields[0]);
        double flowRate = double.parse(fields[1]);
        double batteryVoltage = double.parse(fields[2]);
        double tapOnDuration = double.parse(fields[3]);
        List<dynamic> dataRow = [timestamp, flowRate, batteryVoltage, tapOnDuration];
        _liveDataController.add(dataRow);
        _logger.i('Parsed and added row: $dataRow');
      } catch (e) {
        _logger.e('Error parsing CSV row: $row, Error: $e');
      }
    } else {
      _logger.w('Invalid row format, expected 4 fields, got ${fields.length}: $row');
    }
  }

  Completer<void>? _fetchCompleter;

  Future<int> fetchData(String command, int lastTimestamp, Function(List<dynamic>) onDataReceived, {bool isFullRetrieval = false}) async {
    if (!_isConnected || _uartTx == null || _uartRx == null) {
      _logger.w('Cannot retrieve data: Not connected or UART unavailable');
      return lastTimestamp;
    }
    _isFullRetrieval = isFullRetrieval;
    _logger.i('Starting fetchData with command: $command, isFullRetrieval: $_isFullRetrieval, lastTimestamp: $lastTimestamp');

    try {
      _dataBuffer = '';
      _isReceivingData = false;
      _pendingRow = null;

      // Create a completer to signal when data transfer is complete
      _fetchCompleter = Completer<void>();
      int newRows = 0;
      int latestTimestamp = lastTimestamp;

      // Subscribe to liveDataStream to collect rows
      StreamSubscription<List<dynamic>>? dataSubscription;
      dataSubscription = _liveDataController.stream.listen(
            (dataRow) {
          int rowTimestamp = dataRow[0] as int;
          // Only process rows newer than lastTimestamp (unless full retrieval)
          if (isFullRetrieval || rowTimestamp > lastTimestamp) {
            _logger.d('Received row in fetchData: $dataRow (timestamp: $rowTimestamp)');
            onDataReceived(dataRow); // Forward to caller
            newRows++;
            // Update latestTimestamp if the row's timestamp is newer
            if (rowTimestamp > latestTimestamp) {
              latestTimestamp = rowTimestamp;
            }
          } else {
            _logger.d('Skipped row with timestamp $rowTimestamp <= $lastTimestamp');
          }
        },
        onError: (e) {
          _logger.e('Error in liveDataStream: $e');
          if (!_fetchCompleter!.isCompleted) {
            _fetchCompleter!.completeError(e);
          }
        },
        onDone: () {
          _logger.i('liveDataStream closed unexpectedly');
        },
      );

      // Send the command
      bool success = await writeCommand(command);
      if (!success) {
        _logger.e('Failed to send command: $command');
        await dataSubscription.cancel();
        _fetchCompleter = null;
        return lastTimestamp;
      }
      _logger.i('Sent command: $command');

      // Wait for completion or timeout
      await _fetchCompleter!.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          _logger.w('Data fetch timed out after 60 seconds, rows received: $newRows');
          return;
        },
      );

      // Extended delay to ensure all buffered rows are processed
      await Future.delayed(const Duration(seconds: 1));

      // Cleanup
      await dataSubscription.cancel();
      _fetchCompleter = null;
      _logger.i('Fetch completed: $newRows new rows, latestTimestamp: $latestTimestamp');

      if (newRows > 0) {
        _logger.i('Received $newRows new rows, lastTimestamp updated to $latestTimestamp');
      } else {
        _logger.i('No new data received for command: $command');
      }

      return latestTimestamp;
    } catch (e) {
      _logger.e('Failed to retrieve data: $e');
      await _fetchCompleter?.future.catchError((_) => null);
      _fetchCompleter = null;
      return lastTimestamp;
    } finally {
      if (_fetchCompleter != null && !_fetchCompleter!.isCompleted) {
        _fetchCompleter!.complete();
      }
      _fetchCompleter = null;
    }
  }

  Future<int> retrieveData(int lastTimestamp, Function(List<dynamic>) onDataReceived) async {
    _logger.i('Preparing to retrieve data with lastTimestamp: $lastTimestamp');
    final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _logger.i('Current timestamp: $currentTimestamp');
    if (lastTimestamp >= currentTimestamp - 5) {
      _logger.w('Warning: lastTimestamp ($lastTimestamp) is close to current time ($currentTimestamp), possible overwrite');
    }

    if (lastTimestamp == 0) {
      _logger.w('No valid timestamp found, retrieving all data');
    }
    String command = 'GET_DATA since $lastTimestamp';
    return await fetchData(command, lastTimestamp, onDataReceived);
  }

  Future<int> retrieveAllData(int lastTimestamp, Function(List<dynamic>) onDataReceived) async {
    _logger.i('Preparing to retrieve all data (GET_DATA since 0)');
    String command = 'GET_DATA since 0';
    return await fetchData(command, lastTimestamp, onDataReceived, isFullRetrieval: true);
  }

  void dispose() {
    _characteristicSubscription?.cancel();
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _liveDataController.close();
    _connectionStatusController.close();
    _deviceTimeController.close();
    _scanResultsController.close();
    _isScanningController.close();
    _device?.disconnect();
    FlutterBluePlus.stopScan();
    stopLiveData();
    _fetchCompleter?.complete();
    _fetchCompleter = null;
    _logger.i('BleManager disposed');
  }
}