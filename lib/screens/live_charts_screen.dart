import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import '../widgets/app_drawer.dart';
import '../services/debug_service.dart';

class LiveChartsScreen extends StatefulWidget {
  final Stream<List<dynamic>> liveDataStream;

  const LiveChartsScreen({super.key, required this.liveDataStream});

  @override
  State<LiveChartsScreen> createState() => _LiveChartsScreenState();
}

class _LiveChartsScreenState extends State<LiveChartsScreen> {
  final Logger _logger = Logger();
  final DebugService _debugService = DebugService();
  final List<FlSpot> _tapDurationSpots = [];
  final List<FlSpot> _batteryVoltageSpots = [];
  final List<FlSpot> _waterFlowSpots = [];
  int? _firstTimestamp;
  final List<List<dynamic>> _liveData = [];
  StreamSubscription<List<dynamic>>? _streamSubscription;
  Timer? _updateTimer;
  final List<List<dynamic>> _pendingData = []; // Buffer for batched updates
  static const _updateInterval =
      Duration(milliseconds: 500); // Adjusted for smoother updates
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
      _logger
          .d('Processed ${_pendingData.length} pending data rows, updated UI');
    });
  }

  void _processLiveData(List<dynamic> row) {
    if (row.length != 4) {
      _logger.w(
          'Invalid live data row, expected 4 fields, got ${row.length}: $row');
      _debugService.logError(
          'Invalid live data row, expected 4 fields, got ${row.length}: $row',
          tag: 'CHARTS');
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

      _logger.i(
          'Added live FlSpot: seconds=$secondsSinceFirst, tapDuration=$tapDuration, batteryVoltage=$batteryVoltage, waterFlow=$waterFlow');

      // Debug logging for chart data
      _debugService.logData(
          'Chart data: seconds=$secondsSinceFirst, tapDuration=$tapDuration, batteryVoltage=$batteryVoltage, waterFlow=$waterFlow',
          tag: 'CHARTS');

      if (_tapDurationSpots.every((spot) => spot.y == 0) &&
          _tapDurationSpots.isNotEmpty) {
        _logger.w('All live tap durations are 0.0; device may be idle');
        _debugService.logData(
            'All live tap durations are 0.0; device may be idle',
            tag: 'CHARTS');
      }
      if (_waterFlowSpots.every((spot) => spot.y == 0) &&
          _waterFlowSpots.isNotEmpty) {
        _logger.w('All live water flow rates are 0.0; device may be idle');
        _debugService.logData(
            'All live water flow rates are 0.0; device may be idle',
            tag: 'CHARTS');
      }
    } catch (e) {
      _logger.e('Error processing live data row: $row, Error: $e');
      _debugService.logError('Error processing live data row: $row, Error: $e',
          tag: 'CHARTS');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text(
          'Live Charts',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: const Color(0xFF1E5979),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Water Flow Rate Chart Card
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chart Header
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withOpacity(0.1),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Water Flow Rate (L/s)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Chart Container
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(16),
                    child: _waterFlowSpots.isEmpty
                        ? Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFE0E6ED)),
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.water_drop_outlined,
                                    color: Color(0xFF7F8C8D),
                                    size: 32,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Waiting for water flow data...',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF7F8C8D),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _waterFlowSpots.every((spot) => spot.y == 0)
                            ? Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F9FA),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFFE0E6ED)),
                                ),
                                child: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.water_drop_outlined,
                                        color: Color(0xFF7F8C8D),
                                        size: 32,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'No water flow detected\n(device idle)',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF7F8C8D),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : LineChart(
                                LineChartData(
                                  gridData: FlGridData(
                                    show: true,
                                    drawVerticalLine: true,
                                    horizontalInterval: 1,
                                    verticalInterval: 1,
                                    getDrawingHorizontalLine: (value) {
                                      return FlLine(
                                        color: const Color(0xFFE0E6ED),
                                        strokeWidth: 1,
                                      );
                                    },
                                    getDrawingVerticalLine: (value) {
                                      return FlLine(
                                        color: const Color(0xFFE0E6ED),
                                        strokeWidth: 1,
                                      );
                                    },
                                  ),
                                  titlesData: FlTitlesData(
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 30,
                                        getTitlesWidget: (value, meta) {
                                          if (_firstTimestamp == null) {
                                            return const Text('');
                                          }
                                          final seconds = value.toInt();
                                          return Text(
                                            DateFormat('mm:ss').format(
                                              DateTime
                                                  .fromMillisecondsSinceEpoch(
                                                (_firstTimestamp! + seconds) *
                                                    1000,
                                              ),
                                            ),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF7F8C8D),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 40,
                                        getTitlesWidget: (value, meta) {
                                          return Text(
                                            value.toStringAsFixed(1),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF7F8C8D),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                  ),
                                  borderData: FlBorderData(
                                    show: true,
                                    border: Border.all(
                                      color: const Color(0xFFE0E6ED),
                                      width: 1,
                                    ),
                                  ),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: _waterFlowSpots,
                                      isCurved: true,
                                      color: const Color(0xFF2196F3),
                                      barWidth: 3,
                                      dotData: FlDotData(
                                        show: true,
                                        getDotPainter:
                                            (spot, percent, barData, index) {
                                          return FlDotCirclePainter(
                                            radius: 4,
                                            color: const Color(0xFF2196F3),
                                            strokeWidth: 2,
                                            strokeColor: Colors.white,
                                          );
                                        },
                                      ),
                                      belowBarData: BarAreaData(
                                        show: true,
                                        color: const Color(0xFF2196F3)
                                            .withOpacity(0.1),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                  ),
                ],
              ),
            ),

            // Tap Duration Chart Card
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chart Header
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF44336).withOpacity(0.1),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF44336),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Tap-On Duration (seconds)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Chart Container
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(16),
                    child: _tapDurationSpots.isEmpty
                        ? Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFE0E6ED)),
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.touch_app_outlined,
                                    color: Color(0xFF7F8C8D),
                                    size: 32,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Waiting for tap duration data...',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF7F8C8D),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _tapDurationSpots.every((spot) => spot.y == 0)
                            ? Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F9FA),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFFE0E6ED)),
                                ),
                                child: const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.touch_app_outlined,
                                        color: Color(0xFF7F8C8D),
                                        size: 32,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'No tap activity detected\n(device idle)',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF7F8C8D),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : LineChart(
                                LineChartData(
                                  gridData: FlGridData(
                                    show: true,
                                    drawVerticalLine: true,
                                    horizontalInterval: 1,
                                    verticalInterval: 1,
                                    getDrawingHorizontalLine: (value) {
                                      return FlLine(
                                        color: const Color(0xFFE0E6ED),
                                        strokeWidth: 1,
                                      );
                                    },
                                    getDrawingVerticalLine: (value) {
                                      return FlLine(
                                        color: const Color(0xFFE0E6ED),
                                        strokeWidth: 1,
                                      );
                                    },
                                  ),
                                  titlesData: FlTitlesData(
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 30,
                                        getTitlesWidget: (value, meta) {
                                          if (_firstTimestamp == null) {
                                            return const Text('');
                                          }
                                          final seconds = value.toInt();
                                          return Text(
                                            DateFormat('mm:ss').format(
                                              DateTime
                                                  .fromMillisecondsSinceEpoch(
                                                (_firstTimestamp! + seconds) *
                                                    1000,
                                              ),
                                            ),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF7F8C8D),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    leftTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        reservedSize: 40,
                                        getTitlesWidget: (value, meta) {
                                          return Text(
                                            value.toStringAsFixed(1),
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF7F8C8D),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                  ),
                                  borderData: FlBorderData(
                                    show: true,
                                    border: Border.all(
                                      color: const Color(0xFFE0E6ED),
                                      width: 1,
                                    ),
                                  ),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: _tapDurationSpots,
                                      isCurved: true,
                                      color: const Color(0xFFF44336),
                                      barWidth: 3,
                                      dotData: FlDotData(
                                        show: true,
                                        getDotPainter:
                                            (spot, percent, barData, index) {
                                          return FlDotCirclePainter(
                                            radius: 4,
                                            color: const Color(0xFFF44336),
                                            strokeWidth: 2,
                                            strokeColor: Colors.white,
                                          );
                                        },
                                      ),
                                      belowBarData: BarAreaData(
                                        show: true,
                                        color: const Color(0xFFF44336)
                                            .withOpacity(0.1),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                  ),
                ],
              ),
            ),

            // Battery Voltage Chart Card
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chart Header
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withOpacity(0.1),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 4,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Battery Voltage (V)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Chart Container
                  Container(
                    height: 200,
                    padding: const EdgeInsets.all(16),
                    child: _batteryVoltageSpots.isEmpty
                        ? Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFE0E6ED)),
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.battery_charging_full_outlined,
                                    color: Color(0xFF7F8C8D),
                                    size: 32,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Waiting for battery voltage data...',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF7F8C8D),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : LineChart(
                            LineChartData(
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: true,
                                horizontalInterval: 1,
                                verticalInterval: 1,
                                getDrawingHorizontalLine: (value) {
                                  return FlLine(
                                    color: const Color(0xFFE0E6ED),
                                    strokeWidth: 1,
                                  );
                                },
                                getDrawingVerticalLine: (value) {
                                  return FlLine(
                                    color: const Color(0xFFE0E6ED),
                                    strokeWidth: 1,
                                  );
                                },
                              ),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 30,
                                    getTitlesWidget: (value, meta) {
                                      if (_firstTimestamp == null) {
                                        return const Text('');
                                      }
                                      final seconds = value.toInt();
                                      return Text(
                                        DateFormat('mm:ss').format(
                                          DateTime.fromMillisecondsSinceEpoch(
                                            (_firstTimestamp! + seconds) * 1000,
                                          ),
                                        ),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF7F8C8D),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 40,
                                    getTitlesWidget: (value, meta) {
                                      return Text(
                                        value.toStringAsFixed(1),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF7F8C8D),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                              ),
                              borderData: FlBorderData(
                                show: true,
                                border: Border.all(
                                  color: const Color(0xFFE0E6ED),
                                  width: 1,
                                ),
                              ),
                              lineBarsData: [
                                LineChartBarData(
                                  spots: _batteryVoltageSpots,
                                  isCurved: true,
                                  color: const Color(0xFF4CAF50),
                                  barWidth: 3,
                                  dotData: FlDotData(
                                    show: true,
                                    getDotPainter:
                                        (spot, percent, barData, index) {
                                      return FlDotCirclePainter(
                                        radius: 4,
                                        color: const Color(0xFF4CAF50),
                                        strokeWidth: 2,
                                        strokeColor: Colors.white,
                                      );
                                    },
                                  ),
                                  belowBarData: BarAreaData(
                                    show: true,
                                    color: const Color(0xFF4CAF50)
                                        .withOpacity(0.1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
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
