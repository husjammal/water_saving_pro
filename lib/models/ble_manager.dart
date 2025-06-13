import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';

class BleManager {
  final Logger _logger = Logger();
  final StreamController<String> _connectionStatusController = StreamController.broadcast();
  final StreamController<List<dynamic>> _liveDataController = StreamController.broadcast();
  final StreamController<String> _deviceTimeController = StreamController.broadcast();
  bool isConnected = false;
  bool isScanning = false;
  BluetoothDevice? _device;

  Stream<String> get connectionStatusStream => _connectionStatusController.stream;
  Stream<List<dynamic>> get liveDataStream => _liveDataController.stream;
  Stream<String> get deviceTimeStream => _deviceTimeController.stream;

  BleManager() {
    _setupBluetooth();
  }

  Future<void> _setupBluetooth() async {
    try {
      if (await FlutterBluePlus.isSupported == false) {
        _logger.e('Bluetooth not supported on this device');
        _connectionStatusController.add('Bluetooth not supported');
        return;
      }
      FlutterBluePlus.adapterState.listen((state) {
        if (state == BluetoothAdapterState.on) {
          _logger.i('Bluetooth adapter is on');
        } else {
          _logger.w('Bluetooth adapter is off');
          _connectionStatusController.add('Bluetooth disabled');
        }
      });
    } catch (e) {
      _logger.e('Bluetooth setup failed: $e');
    }
  }

  Future<void> autoConnectToDevice() async {
    if (isConnected) return;
    try {
      isScanning = true;
      _connectionStatusController.add('Scanning for device...');
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult result in results) {
          if (result.device.name.contains('WaterMonitor')) {
            _device = result.device;
            await FlutterBluePlus.stopScan();
            await _connectToDevice();
            break;
          }
        }
      });
      await Future.delayed(const Duration(seconds: 10));
      if (!isConnected) {
        _connectionStatusController.add('No device found');
        isScanning = false;
      }
    } catch (e) {
      _logger.e('Auto-connect failed: $e');
      _connectionStatusController.add('Connection failed: $e');
      isScanning = false;
    }
  }

  Future<void> _connectToDevice() async {
    if (_device == null) return;
    try {
      await _device!.connect();
      isConnected = true;
      isScanning = false;
      _connectionStatusController.add('Connection established');
      _logger.i('Connected to ${_device!.name}');
      // Start reading device time
      _readDeviceTime();
    } catch (e) {
      _logger.e('Connection failed: $e');
      _connectionStatusController.add('Connection failed: $e');
      isConnected = false;
    }
  }

  Future<void> disconnectDevice() async {
    if (_device != null && isConnected) {
      await _device!.disconnect();
      isConnected = false;
      _connectionStatusController.add('Disconnected');
      _logger.i('Disconnected from ${_device!.name}');
    }
  }

  Future<int> retrieveData(int lastTimestamp, Function(List<dynamic>) onData) async {
    if (!isConnected || _device == null) {
      throw Exception('Device not connected');
    }
    try {
      // Simulate BLE data retrieval
      for (int i = lastTimestamp + 1; i <= lastTimestamp + 100; i++) {
        final row = [i, DateTime.now().toString(), 10.0, 20.0]; // Example data
        onData(row);
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return lastTimestamp + 100;
    } catch (e) {
      _logger.e('Data retrieval failed: $e');
      throw e;
    }
  }

  Future<int> retrieveAllData(int lastTimestamp, Function(List<dynamic>) onData) async {
    if (!isConnected || _device == null) {
      throw Exception('Device not connected');
    }
    try {
      // Simulate retrieving all data
      for (int i = 1; i <= 8532; i++) {
        final row = [i, DateTime.now().toString(), 10.0, 20.0]; // Example data
        onData(row);
        await Future.delayed(const Duration(milliseconds: 10));
      }
      return 8532;
    } catch (e) {
      _logger.e('Retrieve all data failed: $e');
      throw e;
    }
  }

  Future<void> startLiveData() async {
    if (!isConnected || _device == null) {
      throw Exception('Device not connected');
    }
    try {
      _logger.i('Starting live data stream');
      // Simulate live data
      Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!isConnected) {
          timer.cancel();
          return;
        }
        final data = [DateTime.now().millisecondsSinceEpoch ~/ 1000, 15.0, 25.0];
        _liveDataController.add(data);
      });
    } catch (e) {
      _logger.e('Start live data failed: $e');
      throw e;
    }
  }

  Future<void> stopLiveData() async {
    _logger.i('Stopping live data stream');
  }

  Future<void> _readDeviceTime() async {
    if (!isConnected || _device == null) return;
    try {
      // Simulate reading device time
      _deviceTimeController.add(DateTime.now().toString());
    } catch (e) {
      _logger.e('Read device time failed: $e');
    }
  }

  Future<void> syncTime() async {
    if (!isConnected || _device == null) {
      throw Exception('Device not connected');
    }
    try {
      // Simulate time sync
      _logger.i('Time synced with device');
      _deviceTimeController.add(DateTime.now().toString());
    } catch (e) {
      _logger.e('Time sync failed: $e');
      throw e;
    }
  }

  void dispose() {
    _connectionStatusController.close();
    _liveDataController.close();
    _deviceTimeController.close();
    disconnectDevice();
    _logger.i('BleManager disposed');
  }
}