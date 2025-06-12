import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

// Typedef to avoid exposing private state class
typedef ReportsScreenState = State<ReportsScreen>;

class ReportsScreen extends StatefulWidget {
  final List<List<dynamic>> csvData;

  const ReportsScreen(this.csvData, {Key? key}) : super(key: key);

  @override
  ReportsScreenState createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final Logger _logger = Logger();
  String _resolution = 'Hourly';
  final List<FlSpot> _tapDurationSpots = [];
  final List<FlSpot> _batteryVoltageSpots = [];
  final List<FlSpot> _waterFlowSpots = [];
  int? _firstTimestamp;

  @override
  void initState() {
    super.initState();
    _updateData();
  }

  Future<void> _updateData() async {
    _logger.i('Updating data for resolution: $_resolution, csvData length: ${widget.csvData.length}');

    if (widget.csvData.isEmpty) {
      _logger.w('No data available in csvData');
      setState(() {
        _tapDurationSpots.clear();
        _batteryVoltageSpots.clear();
        _waterFlowSpots.clear();
        _firstTimestamp = null;
      });
      return;
    }

    // Process data in isolate
    final result = await compute(_processCsvData, {
      'csvData': widget.csvData,
      'resolution': _resolution,
    });

    setState(() {
      _tapDurationSpots.clear();
      _tapDurationSpots.addAll(result['tapDurationSpots']);
      _batteryVoltageSpots.clear();
      _batteryVoltageSpots.addAll(result['batteryVoltageSpots']);
      _waterFlowSpots.clear();
      _waterFlowSpots.addAll(result['waterFlowSpots']);
      _firstTimestamp = result['firstTimestamp'];
    });

    if (_tapDurationSpots.isEmpty) {
      _logger.w('No FlSpots generated; charts will be empty');
    } else if (_tapDurationSpots.every((spot) => spot.y == 0)) {
      _logger.w('All tap durations are 0.0; check data source (code.py or CSV)');
    }
    if (_waterFlowSpots.every((spot) => spot.y == 0)) {
      _logger.w('All water flow rates are 0.0; check data source (code.py or CSV)');
    }
  }

  // Static method for isolate processing
  static Map<String, dynamic> _processCsvData(Map<String, dynamic> input) {
    final Logger logger = Logger();
    final List<List<dynamic>> csvData = input['csvData'];
    final String resolution = input['resolution'];

    Map<String, double> tapDurationSums = {};
    Map<String, double> batteryVoltages = {};
    Map<String, double> waterFlowSums = {};
    int? firstTimestamp;
    bool hasNonZeroTapDuration = false;
    bool hasNonZeroWaterFlow = false;

    // Filter data for the last 7 days for Daily resolution
    List<List<dynamic>> processedData;
    if (resolution == 'Daily') {
      if (csvData.isNotEmpty) {
        int maxTimestamp = csvData.map((row) => row[0] as int).reduce((a, b) => a > b ? a : b);
        int cutoffTimestamp = maxTimestamp - 7 * 24 * 3600; // Last 7 days in seconds
        processedData = csvData.where((row) => row[0] >= cutoffTimestamp).toList();
      } else {
        processedData = [];
      }
    } else if (resolution == 'Hourly') {
      processedData = csvData.length > 120 ? csvData.sublist(csvData.length - 120) : csvData;
    } else {
      processedData = csvData;
    }

    logger.i('Processing ${processedData.length} rows for resolution: $resolution');

    if (resolution == 'Hourly') {
      // Second-level resolution: one FlSpot per row
      List<FlSpot> tapDurationSpots = [];
      List<FlSpot> batteryVoltageSpots = [];
      List<FlSpot> waterFlowSpots = [];
      for (var row in processedData) {
        if (row.length < 5) {
          logger.w('Invalid row format, expected 5 fields, got ${row.length}: $row');
          continue;
        }
        try {
          int timestamp = row[0];
          double waterFlow = row[1];
          double batteryVoltage = row[2];
          double tapDuration = row[3];
          if (tapDuration > 0) hasNonZeroTapDuration = true;
          if (waterFlow > 0) hasNonZeroWaterFlow = true;
          firstTimestamp ??= timestamp;

          double secondsSinceFirst = (timestamp - firstTimestamp!).toDouble();
          tapDurationSpots.add(FlSpot(secondsSinceFirst, tapDuration));
          batteryVoltageSpots.add(FlSpot(secondsSinceFirst, batteryVoltage));
          waterFlowSpots.add(FlSpot(secondsSinceFirst, waterFlow));
          logger.d('Added FlSpot: seconds=$secondsSinceFirst, tapDuration=$tapDuration, batteryVoltage=$batteryVoltage, waterFlow=$waterFlow');
        } catch (e) {
          logger.e('Error processing row: $row, Error: $e');
        }
      }
      return {
        'tapDurationSpots': tapDurationSpots,
        'batteryVoltageSpots': batteryVoltageSpots,
        'waterFlowSpots': waterFlowSpots,
        'firstTimestamp': firstTimestamp,
      };
    } else {
      // Aggregate data for Daily, Weekly, Monthly
      for (var row in processedData) {
        if (row.length < 5) {
          logger.w('Invalid row format, expected 5 fields, got ${row.length}: $row');
          continue;
        }
        try {
          int timestamp = row[0];
          double waterFlow = row[1];
          double batteryVoltage = row[2];
          double tapDuration = row[3];
          if (tapDuration > 0) hasNonZeroTapDuration = true;
          if (waterFlow > 0) hasNonZeroWaterFlow = true;
          DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
          firstTimestamp ??= timestamp;

          String key;
          if (resolution == 'Daily') {
            key = DateFormat('yyyy-MM-dd HH').format(date); // Hourly aggregation
          } else if (resolution == 'Weekly') {
            key = DateFormat('yyyy-MM-ww').format(date);
          } else {
            key = DateFormat('yyyy-MM').format(date);
          }
          tapDurationSums[key] = (tapDurationSums[key] ?? 0) + tapDuration;
          waterFlowSums[key] = (waterFlowSums[key] ?? 0) + waterFlow;
          batteryVoltages[key] = batteryVoltage;
        } catch (e) {
          logger.e('Error processing row: $row, Error: $e');
        }
      }

      logger.i('Aggregated ${tapDurationSums.length} keys: $tapDurationSums');
      logger.i('Water flow sums: $waterFlowSums');
      logger.i('Battery voltages: $batteryVoltages');
      if (!hasNonZeroTapDuration) {
        logger.w('No non-zero tap durations found in CSV data');
      }
      if (!hasNonZeroWaterFlow) {
        logger.w('No non-zero water flow rates found in CSV data');
      }

      List<FlSpot> tapDurationSpots = [];
      List<FlSpot> batteryVoltageSpots = [];
      List<FlSpot> waterFlowSpots = [];
      List<String> sortedKeys = tapDurationSums.keys.toList()..sort();
      // Limit to last 7 aggregated points for Weekly and Monthly
      if (resolution != 'Daily') {
        sortedKeys = sortedKeys.length > 7 ? sortedKeys.sublist(sortedKeys.length - 7) : sortedKeys;
      }
      for (var key in sortedKeys) {
        try {
          DateTime date;
          if (resolution == 'Daily') {
            date = DateFormat('yyyy-MM-dd HH').parse(key);
          } else {
            date = DateFormat('yyyy-MM-dd').parse(key.split('-ww')[0].split('-').take(3).join('-'));
          }
          double hoursSinceFirst = (date.millisecondsSinceEpoch / 1000 - firstTimestamp!) / 3600;
          tapDurationSpots.add(FlSpot(hoursSinceFirst, tapDurationSums[key]!));
          batteryVoltageSpots.add(FlSpot(hoursSinceFirst, batteryVoltages[key]!));
          waterFlowSpots.add(FlSpot(hoursSinceFirst, waterFlowSums[key]!));
          logger.d('Added FlSpot: hours=$hoursSinceFirst, tapDuration=${tapDurationSums[key]}, batteryVoltage=${batteryVoltages[key]}, waterFlow=${waterFlowSums[key]}');
        } catch (e) {
          logger.e('Error parsing date key: $key, Error: $e');
        }
      }

      return {
        'tapDurationSpots': tapDurationSpots,
        'batteryVoltageSpots': batteryVoltageSpots,
        'waterFlowSpots': waterFlowSpots,
        'firstTimestamp': firstTimestamp,
      };
    }
  }

  double _calculateWaterSavingPercentage() {
    double totalTapDuration = _tapDurationSpots.fold(0, (sum, spot) => sum + spot.y);
    int baseline = 3600 * _tapDurationSpots.length;
    return baseline > 0 ? ((baseline - totalTapDuration) / baseline) * 100 : 0;
  }

  double _calculateWaterBillSavings() {
    double totalTapDuration = _tapDurationSpots.fold(0, (sum, spot) => sum + spot.y);
    return totalTapDuration * 0.01;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<String>(
              value: _resolution,
              items: ['Hourly', 'Daily', 'Weekly', 'Monthly']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _resolution = value!;
                  _updateData();
                });
              },
            ),
            const SizedBox(height: 20),
            const Text('Water Flow Rate (L/s)', style: TextStyle(fontSize: 18)),
            Container(
              height: 200,
              padding: const EdgeInsets.all(8.0),
              child: _waterFlowSpots.isEmpty || _waterFlowSpots.every((spot) => spot.y == 0)
                  ? const Center(child: Text('No water flow data available'))
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
                          final date = DateTime.fromMillisecondsSinceEpoch(
                              (_firstTimestamp! + value * 3600).toInt() * 1000);
                          if (_resolution == 'Hourly') {
                            final seconds = value.toInt();
                            return Text(DateFormat('mm:ss').format(
                                DateTime.fromMillisecondsSinceEpoch(
                                    (_firstTimestamp! + seconds) * 1000)));
                          } else if (_resolution == 'Daily') {
                            return Text(DateFormat('MM-dd HH:00').format(date));
                          } else {
                            return Text(DateFormat('MM-dd').format(date));
                          }
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
              child: _tapDurationSpots.isEmpty || _tapDurationSpots.every((spot) => spot.y == 0)
                  ? const Center(child: Text('No tap duration data available'))
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
                          final date = DateTime.fromMillisecondsSinceEpoch(
                              (_firstTimestamp! + value * 3600).toInt() * 1000);
                          if (_resolution == 'Hourly') {
                            final seconds = value.toInt();
                            return Text(DateFormat('mm:ss').format(
                                DateTime.fromMillisecondsSinceEpoch(
                                    (_firstTimestamp! + seconds) * 1000)));
                          } else if (_resolution == 'Daily') {
                            return Text(DateFormat('MM-dd HH:00').format(date));
                          } else {
                            return Text(DateFormat('MM-dd').format(date));
                          }
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
                  ? const Center(child: Text('No battery voltage data available'))
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
                          final date = DateTime.fromMillisecondsSinceEpoch(
                              (_firstTimestamp! + value * 3600).toInt() * 1000);
                          if (_resolution == 'Hourly') {
                            final seconds = value.toInt();
                            return Text(DateFormat('mm:ss').format(
                                DateTime.fromMillisecondsSinceEpoch(
                                    (_firstTimestamp! + seconds) * 1000)));
                          } else if (_resolution == 'Daily') {
                            return Text(DateFormat('MM-dd HH:00').format(date));
                          } else {
                            return Text(DateFormat('MM-dd').format(date));
                          }
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
            Text('Water Saving: ${_calculateWaterSavingPercentage().toStringAsFixed(2)}%'),
            Text('Water Bill Savings: \$${(_calculateWaterBillSavings()).toStringAsFixed(2)}'),
          ],
        ),
      ),
    );
  }
}