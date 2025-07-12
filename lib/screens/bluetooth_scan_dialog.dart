import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'dart:async';

Future<void> showBluetoothScanDialog({
  required BuildContext context,
  required void Function(BluetoothDevice device) onConnect,
  Logger? logger,
}) async {
  final logger0 = logger ?? Logger();
  List<ScanResult> scanResults = [];
  List<BluetoothDevice> systemDevices = [];
  bool isScanning = false;
  StreamSubscription<List<ScanResult>>? scanResultsSubscription;
  StreamSubscription<bool>? isScanningSubscription;
  Timer? scanTimer;
  int remainingSeconds = 15;
  bool isDialogActive = true;

  Future<void> startScan(StateSetter setDialogState) async {
    if (isScanning) {
      logger0.i('Scan already in progress');
      return;
    }
    try {
      setDialogState(() {
        scanResults = [];
        systemDevices = [];
        isScanning = true;
        remainingSeconds = 15;
      });
      var withServices = [Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e")];
      systemDevices = await FlutterBluePlus.systemDevices(withServices);
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      logger0.i('Bluetooth scan started');
    } catch (e) {
      setDialogState(() {
        isScanning = false;
      });
      logger0.e('Failed to start scan: $e');
    }
  }

  void stopScan(StateSetter setDialogState) async {
    try {
      await FlutterBluePlus.stopScan();
      scanTimer?.cancel();
      setDialogState(() {
        isScanning = false;
      });
      logger0.i('Bluetooth scan stopped');
    } catch (e) {
      setDialogState(() {
        isScanning = false;
      });
      logger0.e('Failed to stop scan: $e');
    }
  }

  void refreshScan(StateSetter setDialogState) {
    stopScan(setDialogState);
    startScan(setDialogState);
  }

  void connectToDevice(BluetoothDevice device, BuildContext dialogContext) {
    logger0.i('Initiating connection to ${device.platformName}');
    scanTimer?.cancel();
    scanResultsSubscription?.cancel();
    Navigator.of(dialogContext).pop();
    onConnect(device);
  }

  String getSignalStrengthText(int rssi) {
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -60) return 'Very Good';
    if (rssi >= -70) return 'Good';
    if (rssi >= -80) return 'Fair';
    return 'Poor';
  }

  Color getSignalStrengthColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -60) return Colors.lightGreen;
    if (rssi >= -70) return Colors.orange;
    if (rssi >= -80) return Colors.deepOrange;
    return Colors.red;
  }

  Widget buildDeviceTile(BluetoothDevice device,
      {int? rssi, String? deviceType}) {
    final deviceName =
        device.platformName.isNotEmpty ? device.platformName : 'Unknown Device';
    final deviceId = device.remoteId.toString();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E5979).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            deviceType == 'system'
                ? Icons.bluetooth_connected
                : Icons.bluetooth,
            color: const Color(0xFF1E5979),
            size: 24,
          ),
        ),
        title: Text(
          deviceName,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              deviceId,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF7F8C8D),
              ),
            ),
            if (deviceType != null)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: deviceType == 'system'
                      ? Colors.green.withOpacity(0.1)
                      : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  deviceType == 'system' ? 'Paired Device' : 'Available Device',
                  style: TextStyle(
                    fontSize: 10,
                    color: deviceType == 'system' ? Colors.green : Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        trailing: rssi != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$rssi dBm',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: getSignalStrengthColor(rssi),
                    ),
                  ),
                  Text(
                    getSignalStrengthText(rssi),
                    style: TextStyle(
                      fontSize: 10,
                      color: getSignalStrengthColor(rssi),
                    ),
                  ),
                ],
              )
            : null,
        onTap: () => connectToDevice(device, context),
      ),
    );
  }

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          scanResultsSubscription?.cancel();
          scanResultsSubscription =
              FlutterBluePlus.scanResults.listen((results) {
            setDialogState(() {
              scanResults = results;
            });
            logger0
                .i('Scan results updated: ${scanResults.length} devices found');
          }, onError: (e) {
            logger0.e('Scan error: $e');
            setDialogState(() {
              isScanning = false;
            });
          });

          isScanningSubscription?.cancel();
          isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
            setDialogState(() {
              isScanning = state;
            });
            logger0.i('Scanning state changed: $isScanning');
          }, onError: (e) {
            logger0.e('Scanning subscription error: $e');
            setDialogState(() {
              isScanning = false;
            });
          });

          scanTimer?.cancel();
          scanTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            if (!isDialogActive) return;
            remainingSeconds--;
            setDialogState(() {});
            if (remainingSeconds <= 0) {
              stopScan(setDialogState);
              timer.cancel();
            }
          });

          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(maxHeight: 500),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF1E5979), Color(0xFF2C5F7A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.bluetooth_searching,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Available Devices',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Select a device to connect',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            if (isScanning)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$remainingSeconds s',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.refresh,
                                  color: Colors.white),
                              onPressed: isScanning
                                  ? null
                                  : () => refreshScan(setDialogState),
                              tooltip: 'Refresh Scan',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: isScanning &&
                              scanResults.isEmpty &&
                              systemDevices.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF1E5979)),
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'Scanning for devices...',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFF7F8C8D),
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'This may take a few seconds',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF7F8C8D),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : scanResults.isEmpty && systemDevices.isEmpty
                              ? const Center(
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.bluetooth_disabled,
                                        size: 48,
                                        color: Color(0xFF7F8C8D),
                                      ),
                                      SizedBox(height: 16),
                                      Text(
                                        'No devices found',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Color(0xFF7F8C8D),
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Make sure your device is turned on and nearby',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF7F8C8D),
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                )
                              : ListView(
                                  children: [
                                    if (systemDevices.isNotEmpty) ...[
                                      const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 8),
                                        child: Text(
                                          'Paired Devices',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1E5979),
                                          ),
                                        ),
                                      ),
                                      ...systemDevices.map((device) =>
                                          buildDeviceTile(device,
                                              deviceType: 'system')),
                                      const SizedBox(height: 16),
                                    ],
                                    if (scanResults.isNotEmpty) ...[
                                      const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 8),
                                        child: Text(
                                          'Available Devices',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1E5979),
                                          ),
                                        ),
                                      ),
                                      ...scanResults
                                          .map((result) => buildDeviceTile(
                                                result.device,
                                                rssi: result.rssi,
                                                deviceType: 'available',
                                              )),
                                    ],
                                  ],
                                ),
                    ),
                  ),

                  // Actions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${systemDevices.length + scanResults.length} devices found',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7F8C8D),
                          ),
                        ),
                        TextButton(
                          onPressed: isScanning
                              ? () {
                                  stopScan(setDialogState);
                                }
                              : () => Navigator.of(dialogContext).pop(),
                          style: TextButton.styleFrom(
                            backgroundColor:
                                isScanning ? Colors.red : Colors.transparent,
                            foregroundColor: isScanning
                                ? Colors.white
                                : const Color(0xFF1E5979),
                          ),
                          child: Text(isScanning ? 'Stop Scan' : 'Close'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  ).then((_) {
    isDialogActive = false;
    logger0.i('Scan dialog closed, cleaning up');
    scanTimer?.cancel();
    scanResultsSubscription?.cancel();
    isScanningSubscription?.cancel();
    if (isScanning) {
      FlutterBluePlus.stopScan();
    }
  });
}
