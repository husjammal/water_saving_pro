import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'data_state_model.dart';
import '../services/debug_service.dart';
import 'dart:convert';
import 'dart:async';

class ConnectionStateModel extends ChangeNotifier {
  final Logger _logger = Logger();
  final DebugService _debugService = DebugService();
  String _connectionStatus = 'Disconnected';
  bool _isConnected = false;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _uartTx;
  BluetoothCharacteristic? _uartRx;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<int>>? _characteristicSubscription;
  String _dataBuffer = '';
  bool _isReceivingData = false;
  String? _pendingRow;
  bool _isFullRetrieval = false;
  String _deviceTime = 'Not available';
  bool _isActive = true;
  // SD card status properties
  bool _sdPresent = false;
  bool _fileExists = false;
  int _fileSize = 0;
  int _lastModified = 0;
  final List<void Function(String)> _endOfDataListeners = [];
  final List<void Function(String)> _lineListeners = [];
  final List<void Function(List<int>)> _dataListeners = [];

  // Getters for SD card status
  bool get sdPresent => _sdPresent;
  bool get fileExists => _fileExists;
  int get fileSize => _fileSize;
  int get lastModified => _lastModified;

  final StreamController<List<dynamic>> _liveDataController =
      StreamController<List<dynamic>>.broadcast();

  String get connectionStatus => _connectionStatus;
  bool get isConnected => _isConnected;
  BluetoothDevice? get device => _device;
  Stream<List<dynamic>> get liveDataStream => _liveDataController.stream;
  String get deviceTime => _deviceTime;

  void updateConnectionState(String status, bool isConnected) {
    _connectionStatus = status;
    _isConnected = isConnected;
    _logger.i('Connection state updated: $status, connected: $isConnected');
    notifyListeners();
  }

  void updateDeviceTime(String time) {
    _deviceTime = time;
    _logger.i('Device time updated to: $time');
    notifyListeners();
  }

  void updateSdStatus(bool present, bool exists, int size, int lastModified) {
    _sdPresent = present;
    _fileExists = exists;
    _fileSize = size;
    _lastModified = lastModified;
    _logger.i(
        'SD status updated: present=$present, exists=$exists, size=$size, lastModified=$lastModified');
    notifyListeners();
  }

  Future<bool> requestSdStatus() async {
    return await writeCommand('GET_SD_STATUS');
  }

  void addEndOfDataListener(void Function(String) listener) {
    _endOfDataListeners.add(listener);
  }

  void removeEndOfDataListener(void Function(String) listener) {
    _endOfDataListeners.remove(listener);
  }

  void addLineListener(void Function(String) listener) {
    _lineListeners.add(listener);
  }

  void removeLineListener(void Function(String) listener) {
    _lineListeners.remove(listener);
  }

  void addDataListener(void Function(List<int>) listener) {
    _dataListeners.add(listener);
  }

  void removeDataListener(void Function(List<int>) listener) {
    _dataListeners.remove(listener);
  }

  Future<void> connectToDevice(BluetoothDevice device,
      VoidCallback? onDialogClose, BuildContext context) async {
    _logger.i('Connecting to ${device.platformName}');
    _debugService.logConnection('Connecting to ${device.platformName}',
        tag: 'BT');
    _isActive = true;
    try {
      await device.connect(timeout: const Duration(seconds: 20));
      _logger.i('Connected, requesting MTU...');
      try {
        await device.requestMtu(517);
        _logger.i('Requested MTU of 517 bytes');
      } catch (e) {
        _logger.w('MTU request failed: $e, continuing with default MTU');
      }
      int mtu = await device.mtu.first;
      _logger.i('Negotiated MTU: $mtu bytes');
      _device = device;

      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = device.connectionState.listen(
        (state) {
          _logger.d('Device connection state changed: $state');
          if (state == BluetoothConnectionState.disconnected && _isConnected) {
            _logger.w('Device disconnected unexpectedly');
            _cleanup();
            updateConnectionState('Disconnected', false);
          } else if (state == BluetoothConnectionState.connected &&
              !_isConnected) {
            _logger.i('Device reconnected');
            updateConnectionState('Connection established', true);
          }
        },
        onError: (e) => _logger.e('Connection state error: $e'),
      );

      List<BluetoothService> services = await device.discoverServices();
      BluetoothService? uartService;
      const serviceUUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() ==
            serviceUUID.toLowerCase()) {
          uartService = service;
          break;
        }
      }

      if (uartService == null) {
        _logger.e('UART service not found');
        await device.disconnect();
        updateConnectionState('UART service not found', false);
        onDialogClose?.call();
        return;
      }

      const txUUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
      const rxUUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
      for (var characteristic in uartService.characteristics) {
        if (characteristic.uuid.toString().toLowerCase() ==
            txUUID.toLowerCase()) {
          _uartTx = characteristic;
        } else if (characteristic.uuid.toString().toLowerCase() ==
            rxUUID.toLowerCase()) {
          _uartRx = characteristic;
        }
      }

      if (_uartTx == null || _uartRx == null) {
        _logger.e('Required characteristics not found');
        await device.disconnect();
        updateConnectionState('RX/TX characteristic not found', false);
        onDialogClose?.call();
        return;
      }

      _logger
          .i('RX characteristic properties: ${_uartRx!.properties.toString()}');
      if (_uartRx!.properties.notify || _uartRx!.properties.indicate) {
        try {
          await _uartRx!.setNotifyValue(true);
          _logger.i('Notifications enabled on RX characteristic');
        } catch (e) {
          _logger.e('Failed to enable notifications: $e');
          await device.disconnect();
          updateConnectionState('Failed to enable notifications: $e', false);
          onDialogClose?.call();
          return;
        }
      }

      final dataModel = Provider.of<DataStateModel>(context, listen: false);
      _characteristicSubscription?.cancel();
      _characteristicSubscription = _uartRx!.lastValueStream.listen(
        (value) {
          if (value.isNotEmpty && _isActive) {
            // Debug logging for raw data
            _debugService.logRawData(value, tag: 'BT');

            // Notify data listeners with raw bytes
            for (final listener in _dataListeners) {
              listener(value);
            }

            try {
              String data = utf8.decode(value, allowMalformed: true).trim();
              if (data.isNotEmpty) {
                _logger.d('Raw data received: $data');
                _debugService.logParsedData(data, tag: 'BT');
                _parseReceivedData(data, dataModel);
              }
            } catch (e) {
              _logger.e('Error decoding data: $e');
              _debugService.logError('Error decoding data: $e', tag: 'BT');
            }
          }
        },
        onError: (e) {
          _logger.e('Characteristic subscription error: $e');
          _debugService.logError('Characteristic subscription error: $e',
              tag: 'BT');
        },
      );

      updateConnectionState('Connection established', true);
      onDialogClose?.call();
    } catch (e) {
      _logger.e('Connection error: $e');
      updateConnectionState('Connection failed: $e', false);
      onDialogClose?.call();
    }
  }

  Future<void> disconnectDevice() async {
    if (_device == null) {
      _logger.w('No device to disconnect');
      _cleanup();
      updateConnectionState('Disconnected', false);
      return;
    }

    try {
      await _characteristicSubscription?.cancel();
      if (_uartRx != null) {
        await _uartRx!.setNotifyValue(false);
      }
      await _device!.disconnect();
      _logger.i('Disconnected from ${_device!.platformName}');
    } catch (e) {
      _logger.e('Disconnect error: $e');
    } finally {
      _cleanup();
      updateConnectionState('Disconnected', false);
    }
  }

  Future<bool> writeCommand(String command) async {
    if (!_isConnected || _uartTx == null) {
      _logger.w('Cannot write: Not connected or TX unavailable');
      _debugService.logError('Cannot write: Not connected or TX unavailable',
          tag: 'BT');
      return false;
    }
    try {
      await _uartTx!.write(utf8.encode('$command\n'));
      _logger.i('Wrote command: $command');
      _debugService.logCommand(command, tag: 'BT');
      return true;
    } catch (e) {
      _logger.e('Failed to write command: $e');
      _debugService.logError('Failed to write command: $e', tag: 'BT');
      return false;
    }
  }

  void _processCsvRow(String row,
      {bool isFullRetrieval = false, required DataStateModel dataModel}) {
    _logger.d('Processing row: $row, isFullRetrieval: $isFullRetrieval');
    List<String> fields = row.split(',');
    if (fields.length == 4) {
      try {
        int timestamp = int.parse(fields[0]);
        double flowRate = double.parse(fields[1]);
        double batteryVoltage = double.parse(fields[2]);
        double tapOnDuration = double.parse(fields[3]);
        dataModel.csvData
            .add([timestamp, flowRate, batteryVoltage, tapOnDuration]);
        _liveDataController
            .add([timestamp, flowRate, batteryVoltage, tapOnDuration]);
        _logger.i('Parsed and added row: $fields');
      } catch (e) {
        _logger.e('Error parsing CSV row: $row, Error: $e');
      }
    } else {
      _logger.w(
          'Invalid row format, expected 4 fields, got ${fields.length}: $row');
    }
  }

  void _processSdStatusRow(String row) {
    List<String> fields = row.split(',');
    if (fields.length == 4) {
      try {
        bool sdPresent = int.parse(fields[0]) == 1;
        bool fileExists = int.parse(fields[1]) == 1;
        int fileSize = int.parse(fields[2]);
        int lastModified = int.parse(fields[3]);

        updateSdStatus(sdPresent, fileExists, fileSize, lastModified);
      } catch (e) {
        _logger.e('Error parsing SD status row: $row, Error: $e');
        updateSdStatus(false, false, 0, 0);
      }
    } else {
      _logger.w(
          'Invalid SD status row format, expected 5 fields, got ${fields.length}: $row');
      updateSdStatus(false, false, 0, 0);
    }
  }

  bool _isSdStatusRow(String row) {
    List<String> fields = row.split(',');
    if (fields.length != 4) return false;
    try {
      // Check if all fields can be parsed as integers
      int.parse(fields[0]);
      int.parse(fields[1]);
      int.parse(fields[2]);
      int.parse(fields[3]);
      return true;
    } catch (e) {
      return false;
    }
  }

  void _parseReceivedData(String data, DataStateModel dataModel) {
    _dataBuffer += data;
    _logger
        .d('Buffer updated: $_dataBuffer, isFullRetrieval: $_isFullRetrieval');

    while (_dataBuffer.isNotEmpty) {
      String? lineToNotify;

      // Check for file transfer protocol and other protocol lines first
      if (_dataBuffer.startsWith('FILE_SIZE:')) {
        _logger.i('Received FILE_SIZE: $_dataBuffer');
        lineToNotify = _dataBuffer;
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer == 'FILE_START') {
        _logger.i('Received FILE_START');
        lineToNotify = _dataBuffer;
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer == 'FILE_END') {
        _logger.i('Received FILE_END');
        lineToNotify = _dataBuffer;
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer == 'OK') {
        _logger.i('Received OK');
        lineToNotify = _dataBuffer;
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer == 'PONG') {
        _logger.i('Received PONG');
        lineToNotify = _dataBuffer;
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer.startsWith('ERROR:')) {
        _logger.e('Error received: $_dataBuffer');
        lineToNotify = _dataBuffer;
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer.startsWith('TIME:')) {
        try {
          final timestamp = int.parse(_dataBuffer.split(':')[1].trim());
          final dateTime =
              DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
          _logger.i('Received device time: $dateTime');
          updateDeviceTime(dateTime.toString());
        } catch (e) {
          _logger.e('Invalid TIME response: $_dataBuffer, Error: $e');
          updateDeviceTime('Invalid response');
        }
        lineToNotify = _dataBuffer;
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer == 'SEND_START') {
        _logger.i('Received SEND_START');
        _isReceivingData = true;
        _pendingRow = null;
        lineToNotify = _dataBuffer;
        _dataBuffer = '';
        continue;
      } else if (_dataBuffer == 'SEND_END' && _isReceivingData) {
        _logger.i('Received SEND_END');
        _isReceivingData = false;
        if (_pendingRow != null) {
          if (_isSdStatusRow(_pendingRow!)) {
            _processSdStatusRow(_pendingRow!);
          } else {
            _processCsvRow(_pendingRow!,
                isFullRetrieval: _isFullRetrieval, dataModel: dataModel);
          }
          _pendingRow = null;
        }
        lineToNotify = _dataBuffer;
        _dataBuffer = '';
        _isFullRetrieval = false;
        continue;
      } else if (_dataBuffer == 'END_OF_DATA') {
        _logger.i('Received END_OF_DATA');
        _isReceivingData = false;
        if (_pendingRow != null) {
          _processCsvRow(_pendingRow!,
              isFullRetrieval: _isFullRetrieval, dataModel: dataModel);
          _pendingRow = null;
        }
        // Notify listeners
        for (final listener in _endOfDataListeners) {
          listener('END_OF_DATA');
        }
        // NEW: Notify line listeners directly
        for (final listener in _lineListeners) {
          listener('END_OF_DATA');
        }
        _dataBuffer = '';
        _isFullRetrieval = false;
        continue;
      } else if (_dataBuffer.startsWith('TOTAL_ROWS:')) {
        _logger.i('Received TOTAL_ROWS: $_dataBuffer');
        // Notify line listeners
        for (final listener in _lineListeners) {
          listener(_dataBuffer);
        }
        _dataBuffer = '';
        continue;
      }

      if (_isReceivingData) {
        int newlineIndex = _dataBuffer.indexOf('\n');
        if (newlineIndex == -1 && _dataBuffer.contains(',')) {
          List<String> fields = _dataBuffer.split(',');
          if (fields.length >= 4) {
            _pendingRow = _dataBuffer;
            if (_isSdStatusRow(_pendingRow!)) {
              _processSdStatusRow(_pendingRow!);
            } else {
              _processCsvRow(_pendingRow!,
                  isFullRetrieval: _isFullRetrieval, dataModel: dataModel);
            }
            lineToNotify = _pendingRow;
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
            if (_isSdStatusRow(_pendingRow!)) {
              _processSdStatusRow(_pendingRow!);
            } else {
              _processCsvRow(_pendingRow!,
                  isFullRetrieval: _isFullRetrieval, dataModel: dataModel);
            }
            lineToNotify = _pendingRow;
            _pendingRow = null;
          }
          continue;
        } else {
          _pendingRow = _dataBuffer;
          break;
        }
      } else {
        // For file transfer mode, we don't process data as CSV - it's handled by data listeners
        // Just log and clear the buffer to avoid accumulation
        _logger.d(
            'Received data in non-CSV mode (likely file transfer): $_dataBuffer');
        _dataBuffer = '';
        continue;
      }

      // Notify all line listeners for every line
      if (lineToNotify != null) {
        for (final listener in _lineListeners) {
          listener(lineToNotify);
        }
      }
    }
  }

  void _cleanup() {
    _isActive = false;
    _device = null;
    _uartTx = null;
    _uartRx = null;
    _characteristicSubscription?.cancel();
    _characteristicSubscription = null;
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    _dataBuffer = '';
    _isReceivingData = false;
    _pendingRow = null;
    _isFullRetrieval = false;
    _deviceTime = 'Not available';
    _sdPresent = false;
    _fileExists = false;
    _fileSize = 0;
    _lastModified = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _cleanup();
    _liveDataController.close();
    _logger.i('ConnectionStateModel disposed');
    super.dispose();
  }
}
