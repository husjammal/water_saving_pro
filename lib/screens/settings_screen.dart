import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  final String connectionStatus;
  final bool isConnected;
  final String utcOffset;
  final String deviceTime;
  final VoidCallback onConnectToDevice;
  final VoidCallback onDisconnectDevice;
  final VoidCallback onSyncTime;
  final VoidCallback onReadDeviceTime;
  final ValueChanged<String> onUpdateUtcOffset;
  final ValueChanged<String> onUpdateDeviceTime;

  const SettingsScreen({
    super.key,
    required this.connectionStatus,
    required this.isConnected,
    required this.utcOffset,
    required this.deviceTime,
    required this.onConnectToDevice,
    required this.onDisconnectDevice,
    required this.onSyncTime,
    required this.onReadDeviceTime,
    required this.onUpdateUtcOffset,
    required this.onUpdateDeviceTime,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _deviceTime;

  @override
  void initState() {
    super.initState();
    _deviceTime = widget.deviceTime;
  }

  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceTime != widget.deviceTime) {
      setState(() {
        _deviceTime = widget.deviceTime;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Status: ',
                      style: TextStyle(fontSize: 14),
                    ),
                    Text(
                      widget.connectionStatus,
                      style: TextStyle(
                        fontSize: 14,
                        color: widget.isConnected ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: widget.isConnected ? null : widget.onConnectToDevice,
                  icon: const Icon(Icons.bluetooth),
                  label: const Text('Connect to Device'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: widget.isConnected ? widget.onDisconnectDevice : null,
                  icon: const Icon(Icons.bluetooth_disabled),
                  label: const Text('Disconnect Device'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Time Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('UTC Offset:'),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: widget.utcOffset,
                      items: ['+0', '+3', '+6']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
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
                const SizedBox(height: 16),
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
                  'Device Time: $_deviceTime',
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.left,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}