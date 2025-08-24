import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import '../models/connection_state_model.dart';
import '../models/settings_model.dart';
import '../utils/dialog_utils.dart';
import '../widgets/app_drawer.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'bluetooth_scan_dialog.dart';
import '../services/sound_service.dart';
import '../services/debug_service.dart';
import 'debug_logs_viewer_screen.dart';

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
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final Logger _logger = Logger();
  final SoundService _soundService = SoundService();
  final DebugService _debugService = DebugService();

  @override
  void initState() {
    super.initState();
    _logger.i('SettingsScreen initialized');
    // Stop live data when entering settings
    Future.microtask(() async {
      final connectionModel =
          Provider.of<ConnectionStateModel>(context, listen: false);
      if (connectionModel.isConnected) {
        _logger.i('[STOP_LIVE_DATA] Sent from SettingsScreen');
        await connectionModel.writeCommand('STOP_LIVE_DATA');
      }
    });
  }

  @override
  void dispose() {
    _logger.i('SettingsScreen disposed');
    super.dispose();
  }

  Future<void> _showMessageDialog(String title, String message) async {
    if (mounted) {
      await DialogUtils.showMessageDialog(
        context: context,
        title: title,
        message: message,
      );
    }
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

  Future<void> _requestSdStatus() async {
    final connectionModel =
        Provider.of<ConnectionStateModel>(context, listen: false);
    if (!connectionModel.isConnected) {
      _logger.w('Cannot request SD status: Not connected');
      await DialogUtils.showErrorDialog(
          context: context,
          title: 'SD Status Error',
          message: 'Please connect to the device first.');
      return;
    }
    try {
      bool success = await connectionModel.requestSdStatus();
      if (!success) {
        await DialogUtils.showErrorDialog(
            context: context,
            title: 'SD Status Error',
            message: 'Failed to send GET_SD_STATUS command.');
      }
    } catch (e) {
      _logger.e('Failed to request SD status: $e');
      await DialogUtils.showErrorDialog(
          context: context,
          title: 'SD Status Error',
          message: 'Failed to request SD status: $e');
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes == 0) return '0 KB';
    double kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(2)} KB';
    double mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  String _formatLastModified(int timestamp) {
    if (timestamp == 0) return 'Not available';
    try {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
    } catch (e) {
      _logger.e('Failed to format last modified: $e');
      return 'Invalid timestamp';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionStateModel>(
      builder: (context, connectionModel, child) {
        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          drawer: const AppDrawer(
            onDisableAutoStartLiveData: null,
            onEnableAutoStartLiveData: null,
            onNavigateToRetrieveData: null,
            onNavigateToSettings: null,
          ),
          appBar: AppBar(
            title: const Text(
              'Settings',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
            backgroundColor: const Color(0xFF1E5979),
            actions: [
              IconButton(
                icon: const Icon(Icons.exit_to_app, color: Colors.white),
                tooltip: 'Exit',
                onPressed: () {
                  Navigator.maybePop(context);
                },
              ),
            ],
            elevation: 0,
            centerTitle: true,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Device Connection Card
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2196F3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Device Connection',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: connectionModel.isConnected
                                ? const Color(0xFFE8F5E8)
                                : const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: connectionModel.isConnected
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFF44336),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                connectionModel.isConnected
                                    ? Icons.bluetooth_connected
                                    : Icons.bluetooth_disabled,
                                color: connectionModel.isConnected
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFFF44336),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Status: ${connectionModel.connectionStatus}',
                                      style: TextStyle(
                                        color: connectionModel.isConnected
                                            ? const Color(0xFF4CAF50)
                                            : const Color(0xFFF44336),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (connectionModel.isConnected)
                                ElevatedButton(
                                  onPressed: widget.onDisconnectDevice,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF44336),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 2,
                                  ),
                                  child: const Text(
                                    'Disconnect',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => showBluetoothScanDialog(
                            context: context,
                            onConnect: (device) {
                              Provider.of<ConnectionStateModel>(context,
                                      listen: false)
                                  .connectToDevice(
                                device,
                                () async {
                                  // Automatically sync time after connection
                                  if (mounted) {
                                    await Future.delayed(
                                        const Duration(seconds: 1));
                                    widget.onSyncTime();
                                  }
                                },
                                context,
                              );
                            },
                            logger: _logger,
                          ),
                          icon: const Icon(Icons.bluetooth_searching,
                              color: Colors.white),
                          label: const Text(
                            'Scan for Devices',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E5979),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Time Synchronization Card
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Time Synchronization',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE0E6ED)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                color: Color(0xFF1E5979),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Device Time: ${_formatDeviceTime(connectionModel.deviceTime, widget.utcOffset)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF2C3E50),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: const Color(0xFFE0E6ED)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: widget.utcOffset,
                                    isExpanded: true,
                                    icon: const Icon(
                                      Icons.keyboard_arrow_down,
                                      color: Color(0xFF1E5979),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    items: [
                                      '+0',
                                      '+1',
                                      '+2',
                                      '+3',
                                      '+4',
                                      '+5',
                                      '+6',
                                      '+7',
                                      '+8',
                                      '+9',
                                      '+10',
                                      '+11',
                                      '+12',
                                      '-1',
                                      '-2',
                                      '-3',
                                      '-4',
                                      '-5',
                                      '-6',
                                      '-7',
                                      '-8',
                                      '-9',
                                      '-10',
                                      '-11',
                                      '-12'
                                    ].map((String value) {
                                      return DropdownMenuItem<String>(
                                        value: value,
                                        child: Text(
                                          'UTC$value',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      if (newValue != null) {
                                        widget.onUpdateUtcOffset(newValue);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: widget.onSyncTime,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4CAF50),
                                minimumSize: const Size(120, 50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 2,
                              ),
                              child: const Text(
                                'Sync Time',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: widget.onReadDeviceTime,
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          label: const Text(
                            'Read Device Time',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E5979),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Sound Settings Card
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF9C27B0),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Sound Settings',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE0E6ED)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF9C27B0)
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.volume_up,
                                      color: Color(0xFF9C27B0),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Water Flow Sounds',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF2C3E50),
                                          ),
                                        ),
                                        Text(
                                          'Play sounds when water starts/stops flowing',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF7F8C8D),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _soundService.soundsEnabled,
                                    onChanged: (value) {
                                      setState(() {
                                        _soundService.setSoundsEnabled(value);
                                      });
                                    },
                                    activeColor: const Color(0xFF9C27B0),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E8),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF4CAF50)
                                        .withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline,
                                      color: Color(0xFF4CAF50),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Sounds will play when water flow is detected or stops',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF4CAF50),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  // Test water flow start sound
                                  await _soundService.playWaterFlowStart();
                                  // Stop after 2 seconds
                                  Future.delayed(const Duration(seconds: 2),
                                      () {
                                    _soundService.playWaterFlowStop();
                                  });
                                },
                                icon: const Icon(Icons.play_arrow,
                                    color: Colors.white),
                                label: const Text(
                                  'Test Sounds',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF9C27B0),
                                  minimumSize: const Size(double.infinity, 40),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Water Calculation Settings Card
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF00BCD4),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Water Calculation Settings',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Consumer<SettingsModel>(
                          builder: (context, settingsModel, child) {
                            return Column(
                              children: [
                                // Max Flow Rate Setting
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8F9FA),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFFE0E6ED)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF00BCD4)
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.water_drop,
                                              color: Color(0xFF00BCD4),
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Maximum Flow Rate',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF2C3E50),
                                                  ),
                                                ),
                                                Text(
                                                  'Used for water saving calculations',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF7F8C8D),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Slider(
                                              value: settingsModel.maxFlowRate,
                                              min: 0.5,
                                              max: 10.0,
                                              divisions: 95,
                                              activeColor:
                                                  const Color(0xFF00BCD4),
                                              inactiveColor:
                                                  const Color(0xFFE0E6ED),
                                              onChanged: (value) {
                                                settingsModel
                                                    .updateMaxFlowRate(value);
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF00BCD4)
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color:
                                                      const Color(0xFF00BCD4)),
                                            ),
                                            child: Text(
                                              '${settingsModel.maxFlowRate.toStringAsFixed(1)} L/s',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF00BCD4),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Unit Price Setting
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8F9FA),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFFE0E6ED)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF4CAF50)
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.attach_money,
                                              color: Color(0xFF4CAF50),
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          const Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Water Unit Price',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF2C3E50),
                                                  ),
                                                ),
                                                Text(
                                                  'Cost per liter for savings calculation',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF7F8C8D),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Slider(
                                              value: settingsModel.unitPrice,
                                              min: 0.1,
                                              max: 5.0,
                                              divisions: 49,
                                              activeColor:
                                                  const Color(0xFF4CAF50),
                                              inactiveColor:
                                                  const Color(0xFFE0E6ED),
                                              onChanged: (value) {
                                                settingsModel
                                                    .updateUnitPrice(value);
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF4CAF50)
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color:
                                                      const Color(0xFF4CAF50)),
                                            ),
                                            child: Text(
                                              '\$${settingsModel.unitPrice.toStringAsFixed(2)}/L',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF4CAF50),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Splash Duration Setting
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3498DB)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.timer,
                                        color: Color(0xFF3498DB),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Splash Screen Duration',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF2C3E50),
                                            ),
                                          ),
                                          Text(
                                            'Duration of animated logo display on startup',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF7F8C8D),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Slider(
                                        value: settingsModel.splashDuration
                                            .toDouble(),
                                        min: 1.0,
                                        max: 10.0,
                                        divisions: 9,
                                        activeColor: const Color(0xFF3498DB),
                                        inactiveColor: const Color(0xFFE0E6ED),
                                        onChanged: (value) {
                                          settingsModel.updateSplashDuration(
                                              value.toInt());
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3498DB)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                            color: const Color(0xFF3498DB)),
                                      ),
                                      child: Text(
                                        '${settingsModel.splashDuration}s',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF3498DB),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE8F5E8),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF4CAF50)
                                          .withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.info_outline,
                                        color: Color(0xFF4CAF50),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          'These settings are used to calculate water savings and cost savings in reports',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF4CAF50),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Debug Settings Card
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF6C757D),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Debug Settings',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE0E6ED)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF6C757D)
                                          .withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.bug_report,
                                      color: Color(0xFF6C757D),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Console Debug Logging',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF2C3E50),
                                          ),
                                        ),
                                        Text(
                                          'Enable detailed console logging for debugging',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF7F8C8D),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: _debugService.isEnabled,
                                    onChanged: (value) {
                                      setState(() {
                                        if (value) {
                                          _debugService.enableDebugging();
                                        } else {
                                          _debugService.disableDebugging();
                                        }
                                      });
                                    },
                                    activeColor: const Color(0xFF4CAF50),
                                    inactiveThumbColor: const Color(0xFF9E9E9E),
                                    inactiveTrackColor: const Color(0xFFE0E0E0),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE8F5E8),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF4CAF50)
                                        .withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline,
                                      color: Color(0xFF4CAF50),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'Debug logs are sent to console and can be viewed in Android Studio/VS Code',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF4CAF50),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Column(
                                children: [
                                  // First row: Clear Buffer and Export Logs
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            _debugService.clearBuffer();
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Debug buffer cleared'),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.clear,
                                              color: Colors.white, size: 16),
                                          label: const Text(
                                            'Clear Buffer',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF6C757D),
                                            minimumSize:
                                                const Size(double.infinity, 40),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            elevation: 2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: () async {
                                            final result = await _debugService
                                                .exportLogsToFile();
                                            if (result['success']) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                      'Debug logs exported to ${result['fileName']}'),
                                                  duration: const Duration(
                                                      seconds: 3),
                                                ),
                                              );
                                            } else {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                      'Export failed: ${result['error']}'),
                                                  backgroundColor: Colors.red,
                                                  duration: const Duration(
                                                      seconds: 3),
                                                ),
                                              );
                                            }
                                          },
                                          icon: const Icon(Icons.download,
                                              color: Colors.white, size: 16),
                                          label: const Text(
                                            'Export Logs',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF1E5979),
                                            minimumSize:
                                                const Size(double.infinity, 40),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            elevation: 2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Second row: View Logs (full width)
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const DebugLogsViewerScreen(),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.visibility,
                                        color: Colors.white, size: 16),
                                    label: const Text(
                                      'View Logs',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2196F3),
                                      minimumSize:
                                          const Size(double.infinity, 40),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      elevation: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // SD Card Status Card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 4,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF9800),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'SD Card Status',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2C3E50),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _requestSdStatus,
                          icon: const Icon(Icons.storage, color: Colors.white),
                          label: const Text(
                            'Check SD Card Status',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF9800),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE0E6ED)),
                          ),
                          child: Column(
                            children: [
                              _buildStatusRow(
                                Icons.sd_storage,
                                'SD Card',
                                connectionModel.sdPresent
                                    ? 'Inserted'
                                    : 'Not Inserted',
                                connectionModel.sdPresent
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFFF44336),
                              ),
                              const SizedBox(height: 12),
                              _buildStatusRow(
                                Icons.description,
                                'Data.csv',
                                connectionModel.fileExists
                                    ? 'Exists'
                                    : 'Does Not Exist',
                                connectionModel.fileExists
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFFF44336),
                              ),
                              const SizedBox(height: 12),
                              _buildStatusRow(
                                Icons.storage,
                                'File Size',
                                _formatFileSize(connectionModel.fileSize),
                                const Color(0xFF1E5979),
                              ),
                              const SizedBox(height: 12),
                              _buildStatusRow(
                                Icons.access_time,
                                'Last Modified',
                                _formatLastModified(
                                    connectionModel.lastModified),
                                const Color(0xFF1E5979),
                              ),
                            ],
                          ),
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

  Widget _buildStatusRow(
      IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(
          icon,
          color: color,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF7F8C8D),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
