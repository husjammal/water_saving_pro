import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import '../models/connection_state_model.dart';
import 'dart:async';
import 'package:intl/intl.dart';

class SettingsScreen extends StatefulWidget {
  final String utcOffset;
  final VoidCallback onDisconnectDevice;
  final VoidCallback onSyncTime;
  final VoidCallback onReadDeviceTime;
  final ValueChanged<String> onUpdateUtcOffset;

  const SettingsScreen({
    super.key,
    required this.utcOffset,
    required this.onDisconnectDevice,
    required this.onSyncTime,
    required this.onReadDeviceTime,
    required this.onUpdateUtcOffset,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Logger _logger = Logger();
  List<ScanResult> _scanResults = [];
  List<BluetoothDevice> _systemDevices = [];
  bool _isScanning = false;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  Timer? _scanTimer;

  @override
  void initState() {
    super.initState();
    _setupBluetoothSubscriptions();
    _logger.i('SettingsScreen initialized');
  }

  void _setupBluetoothSubscriptions() {
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      if (mounted) {
        setState(() {
          _isScanning = state;
        });
        _logger.i('Scanning state changed: $_isScanning');
      }
    }, onError: (e) {
      _logger.e('Scanning subscription error: $e');
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _scanTimer?.cancel();
    FlutterBluePlus.stopScan().catchError((e) {
      _logger.e('Error stopping scan on dispose: $e');
    });
    _logger.i('SettingsScreen disposed');
    super.dispose();
  }

  Future<void> _showMessageDialog(String title, String message) async {
    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _startScan() async {
    if (_isScanning) {
      _logger.i('Scan already in progress');
      _showMessageDialog('Scan Info', 'A scan is already in progress.');
      return;
    }
    try {
      setState(() {
        _scanResults = [];
        _systemDevices = [];
        _isScanning = true;
      });
      var withServices = [Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e")];
      _systemDevices = await FlutterBluePlus.systemDevices(withServices);
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      _logger.i('Bluetooth scan started');
      _showScanDialog();
    } catch (e) {
      _showMessageDialog('Scan Error', 'Failed to start scan: $e');
      setState(() {
        _isScanning = false;
      });
      _logger.e('Failed to start scan: $e');
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      _scanTimer?.cancel();
      setState(() {
        _isScanning = false;
      });
      _logger.i('Bluetooth scan stopped');
    } catch (e) {
      _showMessageDialog('Scan Error', 'Failed to stop scan: $e');
      setState(() {
        _isScanning = false;
      });
      _logger.e('Failed to stop scan: $e');
    }
  }

  void _connectToDevice(BluetoothDevice device, BuildContext dialogContext) {
    _logger.i('Initiating connection to ${device.platformName}');
    _scanTimer?.cancel();
    _logger.i('Scan timer canceled in _connectToDevice');
    _scanResultsSubscription?.cancel();
    Provider.of<ConnectionStateModel>(context, listen: false).connectToDevice(
      device,
      () {
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop(); // Close scan dialog
          if (mounted) {
            Navigator.of(context).pop(); // Pop SettingsScreen
          }
        }
      },
      dialogContext, // Pass BuildContext
    );
  }

  void _refreshScan() {
    _stopScan().then((_) => _startScan());
  }

  void _showScanDialog() {
    int remainingSeconds = 15;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          _scanResultsSubscription?.cancel();
          _scanResultsSubscription =
              FlutterBluePlus.scanResults.listen((results) {
            if (mounted) {
              setDialogState(() {
                _scanResults = results;
              });
              _logger.i(
                  'Scan results updated: ${_scanResults.length} devices found');
            }
          }, onError: (e) {
            _logger.e('Scan error: $e');
            if (mounted) {
              setDialogState(() {
                _isScanning = false;
              });
            }
          });

          _scanTimer?.cancel();
          _scanTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!mounted || !dialogContext.mounted) {
              _logger.w(
                  'Scan timer stopped: SettingsScreen or dialog not mounted');
              timer.cancel();
              return;
            }
            setDialogState(() {
              remainingSeconds--;
            });
            if (remainingSeconds <= 0) {
              _stopScan();
              timer.cancel();
            }
          });

          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Text(
                    'Available Devices',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Row(
                  children: [
                    if (_isScanning)
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Text('$remainingSeconds s'),
                      ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _isScanning ? null : _refreshScan,
                      tooltip: 'Refresh Scan',
                    ),
                  ],
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: _isScanning &&
                      _scanResults.isEmpty &&
                      _systemDevices.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Scanning for devices...'),
                        ],
                      ),
                    )
                  : _scanResults.isEmpty && _systemDevices.isEmpty
                      ? const Center(child: Text('No devices found'))
                      : ListView(
                          children: [
                            ..._systemDevices.map((device) => ListTile(
                                  title: Text(device.platformName.isNotEmpty
                                      ? device.platformName
                                      : 'Unknown Device'),
                                  subtitle: Text(device.remoteId.toString()),
                                  onTap: () =>
                                      _connectToDevice(device, dialogContext),
                                )),
                            ..._scanResults.map((result) => ListTile(
                                  title: Text(
                                      result.device.platformName.isNotEmpty
                                          ? result.device.platformName
                                          : result.advertisementData.advName
                                                  .isNotEmpty
                                              ? result.advertisementData.advName
                                              : 'Unknown Device'),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(result.device.remoteId.toString()),
                                      if (result.advertisementData.serviceUuids
                                          .isNotEmpty)
                                        Text(
                                          'Services: ${result.advertisementData.serviceUuids.join(', ')}',
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                    ],
                                  ),
                                  trailing: Text('${result.rssi} dBm'),
                                  onTap: () => _connectToDevice(
                                      result.device, dialogContext),
                                )),
                          ],
                        ),
            ),
            actions: [
              TextButton(
                onPressed: _isScanning
                    ? () {
                        _stopScan();
                        setDialogState(() {});
                      }
                    : () => Navigator.of(dialogContext).pop(),
                child: Text(_isScanning ? 'Stop Scan' : 'Close'),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      _logger.i('Scan dialog closed, cleaning up');
      _scanTimer?.cancel();
      _scanResultsSubscription?.cancel();
      if (_isScanning) {
        _stopScan();
      }
    });
  }

  String _formatDeviceTime(String deviceTime, String utcOffset) {
    if (deviceTime == 'Not available' ||
        deviceTime == 'Reading...' ||
        deviceTime == 'Invalid response') {
      return deviceTime;
    }
    try {
      final dateTime = DateTime.parse(deviceTime);
      final offsetHours = int.parse(utcOffset.replaceFirst('+', ''));
      final offsetDuration = Duration(hours: offsetHours);
      final adjustedTime = dateTime.add(offsetDuration);
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(adjustedTime);
    } catch (e) {
      _logger.e('Failed to format device time: $e');
      return 'Invalid time';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionStateModel>(
      builder: (context, connectionModel, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Device Connection',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text(
                          'Status: ',
                          style: TextStyle(fontSize: 14),
                        ),
                        Flexible(
                          child: Text(
                            connectionModel.connectionStatus,
                            style: TextStyle(
                              fontSize: 14,
                              color: connectionModel.isConnected
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                              overflow: TextOverflow.ellipsis,
                            ),
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed:
                          connectionModel.isConnected ? null : _startScan,
                      icon: const Icon(Icons.bluetooth_searching),
                      label: const Text('Scan for Devices'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: connectionModel.isConnected
                          ? widget.onDisconnectDevice
                          : null,
                      icon: const Icon(Icons.bluetooth_disabled),
                      label: const Text('Disconnect Device'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Time Settings',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('UTC Offset:'),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: widget.utcOffset,
                          items: ['+0', '+3', '+6']
                              .map((e) =>
                                  DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              widget.onUpdateUtcOffset(value);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: widget.onSyncTime,
                      icon: const Icon(Icons.sync),
                      label: const Text('Sync Time'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: widget.onReadDeviceTime,
                      icon: const Icon(Icons.access_time),
                      label: const Text('Read Device Time'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Device Time: ${_formatDeviceTime(connectionModel.deviceTime, widget.utcOffset)}',
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.left,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
