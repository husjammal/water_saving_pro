import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'data_state_model.dart';
import 'dart:convert';
import 'dart:async';

class ConnectionStateModel extends ChangeNotifier {
  final Logger _logger = Logger();
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

  Future<void> connectToDevice(
      BluetoothDevice device, VoidCallback? onDialogClose, BuildContext context) async {
    _logger.i('Connecting to ${device.platformName}');
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
          } else if (state == BluetoothConnectionState.connected && !_isConnected) {
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
        if (service.uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
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
        if (characteristic.uuid.toString().toLowerCase() == txUUID.toLowerCase()) {
          _uartTx = characteristic;
        } else if (characteristic.uuid.toString().toLowerCase() == rxUUID.toLowerCase()) {
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

      _logger.i('RX characteristic properties: ${_uartRx!.properties.toString()}');
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
            try {
              String data = utf8.decode(value, allowMalformed: true).trim();
              if (data.isNotEmpty) {
                _logger.d('Raw data received: $data');
                _parseReceivedData(data, dataModel);
              }
            } catch (e) {
              _logger.e('Error decoding data: $e');
            }
          }
        },
        onError: (e) => _logger.e('Characteristic subscription error: $e'),
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

  void _processCsvRow(String row, {bool isFullRetrieval = false, required DataStateModel dataModel}) {
    _logger.d('Processing row: $row, isFullRetrieval: $isFullRetrieval');
    List<String> fields = row.split(',');
    if (fields.length == 4) {
      try {
        int timestamp = int.parse(fields[0]);
        double flowRate = double.parse(fields[1]);
        double batteryVoltage = double.parse(fields[2]);
        double tapOnDuration = double.parse(fields[3]);
        dataModel.csvData.add([timestamp, flowRate, batteryVoltage, tapOnDuration]);
        _liveDataController.add([timestamp, flowRate, batteryVoltage, tapOnDuration]);
        _logger.i('Parsed and added row: $fields');
      } catch (e) {
        _logger.e('Error parsing CSV row: $row, Error: $e');
      }
    } else {
      _logger.w('Invalid row format, expected 4 fields, got ${fields.length}: $row');
    }
  }

  void _parseReceivedData(String data, DataStateModel dataModel) {
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
          _logger.i('Received device time: $dateTime');
          updateDeviceTime(dateTime.toString());
        } catch (e) {
          _logger.e('Invalid TIME response: $_dataBuffer, Error: $e');
          updateDeviceTime('Invalid response');
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
          _processCsvRow(_pendingRow!, isFullRetrieval: _isFullRetrieval, dataModel: dataModel);
          _pendingRow = null;
        }
        _dataBuffer = '';
        _isFullRetrieval = false;
        continue;
      } else if (_dataBuffer == 'END_OF_DATA') {
        _logger.i('Received END_OF_DATA');
        _isReceivingData = false;
        if (_pendingRow != null) {
          _processCsvRow(_pendingRow!, isFullRetrieval: _isFullRetrieval, dataModel: dataModel);
          _pendingRow = null;
        }
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
            _processCsvRow(_pendingRow!, isFullRetrieval: _isFullRetrieval, dataModel: dataModel);
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
            _processCsvRow(_pendingRow!, isFullRetrieval: _isFullRetrieval, dataModel: dataModel);
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