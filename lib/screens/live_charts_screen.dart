import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

class LiveChartsScreen extends StatefulWidget {
  final Stream<List<dynamic>> liveDataStream;

  const LiveChartsScreen({super.key, required this.liveDataStream});

  @override
  State<LiveChartsScreen> createState() => _LiveChartsScreenState();
}

class _LiveChartsScreenState extends State<LiveChartsScreen> {
  final Logger _logger = Logger();
  final List<FlSpot> _tapDurationSpots = [];
  final List<FlSpot> _batteryVoltageSpots = [];
  final List<FlSpot> _waterFlowSpots = [];
  int? _firstTimestamp;
  final List<List<dynamic>> _liveData = [];
  StreamSubscription<List<dynamic>>? _streamSubscription;
  Timer? _updateTimer;
  final List<List<dynamic>> _pendingData = []; // Buffer for batched updates
  static const _updateInterval = Duration(milliseconds: 500); // Adjusted for smoother updates
  static const _maxDataPoints = 120; // Max points to prevent memory issues

  @override
  void initState() {
    super.initState();
    _subscribeToDataStream();
    _startUpdateTimer();
  }

  void _subscribeToDataStream() {
    _streamSubscription = widget.liveDataStream.listen(
          (data) {
        if (!mounted) {
          _logger.w('Received data but widget is unmounted, skipping: $data');
          return;
        }
        _logger.d('Received live data: $data');
        _pendingData.add(data);
      },
      onError: (e) {
        _logger.e('Stream error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Data stream error: $e')),
          );
        }
      },
      cancelOnError: false,
    );
    _logger.i('Subscribed to live data stream');
  }

  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(_updateInterval, (_) {
      if (_pendingData.isEmpty || !mounted) return;
      setState(() {
        for (var row in _pendingData) {
          _processLiveData(row);
        }
        _pendingData.clear();
      });
      _logger.d('Processed ${_pendingData.length} pending data rows, updated UI');
    });
  }

  void _processLiveData(List<dynamic> row) {
    if (row.length != 4) {
      _logger.w('Invalid live data row, expected 4 fields, got ${row.length}: $row');
      return;
    }
    try {
      int timestamp = row[0] as int;
      double waterFlow = row[1] as double; // moisture as water_flow_rate
      double batteryVoltage = row[2] as double; // voltage as battery_voltage
      double tapDuration = row[3] as double; // is_watering as tap_on_duration

      _liveData.add(row);
      _firstTimestamp ??= timestamp;

      if (_liveData.length > _maxDataPoints) {
        _liveData.removeAt(0);
        _tapDurationSpots.removeAt(0);
        _batteryVoltageSpots.removeAt(0);
        _waterFlowSpots.removeAt(0);
      }

      double secondsSinceFirst = (timestamp - _firstTimestamp!).toDouble();
      _tapDurationSpots.add(FlSpot(secondsSinceFirst, tapDuration));
      _batteryVoltageSpots.add(FlSpot(secondsSinceFirst, batteryVoltage));
      _waterFlowSpots.add(FlSpot(secondsSinceFirst, waterFlow));

      _logger.i('Added live FlSpot: seconds=$secondsSinceFirst, tapDuration=$tapDuration, batteryVoltage=$batteryVoltage, waterFlow=$waterFlow');

      if (_tapDurationSpots.every((spot) => spot.y == 0) && _tapDurationSpots.isNotEmpty) {
        _logger.w('All live tap durations are 0.0; device may be idle');
      }
      if (_waterFlowSpots.every((spot) => spot.y == 0) && _waterFlowSpots.isNotEmpty) {
        _logger.w('All live water flow rates are 0.0; device may be idle');
      }
    } catch (e) {
      _logger.e('Error processing live data row: $row, Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Charts')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Water Flow Rate (L/s)', style: TextStyle(fontSize: 18)),
            Container(
              height: 200,
              padding: const EdgeInsets.all(8.0),
              child: _waterFlowSpots.isEmpty
                  ? const Center(child: Text('Waiting for water flow data...'))
                  : _waterFlowSpots.every((spot) => spot.y == 0)
                  ? const Center(child: Text('No water flow detected (device idle)'))
                  : LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: _waterFlowSpots,
                      isCurved: true,
                      color: Colors.orange,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (_firstTimestamp == null) return const Text('');
                          final seconds = value.toInt();
                          return Text(
                            DateFormat('mm:ss').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                (_firstTimestamp! + seconds) * 1000,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                  ),
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: true),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Tap-On Duration (seconds)', style: TextStyle(fontSize: 18)),
            Container(
              height: 200,
              padding: const EdgeInsets.all(8.0),
              child: _tapDurationSpots.isEmpty
                  ? const Center(child: Text('Waiting for tap duration data...'))
                  : _tapDurationSpots.every((spot) => spot.y == 0)
                  ? const Center(child: Text('No tap activity detected (device idle)'))
                  : LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: _tapDurationSpots,
                      isCurved: true,
                      color: Colors.blue,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (_firstTimestamp == null) return const Text('');
                          final seconds = value.toInt();
                          return Text(
                            DateFormat('mm:ss').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                (_firstTimestamp! + seconds) * 1000,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                  ),
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: true),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Battery Voltage (V)', style: TextStyle(fontSize: 18)),
            Container(
              height: 200,
              padding: const EdgeInsets.all(8.0),
              child: _batteryVoltageSpots.isEmpty
                  ? const Center(child: Text('Waiting for battery voltage data...'))
                  : LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: _batteryVoltageSpots,
                      isCurved: true,
                      color: Colors.green,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (_firstTimestamp == null) return const Text('');
                          final seconds = value.toInt();
                          return Text(
                            DateFormat('mm:ss').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                (_firstTimestamp! + seconds) * 1000,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                  ),
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _streamSubscription?.cancel();
    _logger.i('LiveChartsScreen disposed, timers canceled');
    super.dispose();
  }
}