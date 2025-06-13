import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';

class ReportsScreen extends StatefulWidget {
  final List<List<dynamic>> csvData;

  const ReportsScreen(this.csvData, {super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final Logger _logger = Logger();
  String _selectedResolution = 'Hourly';
  DateTime _selectedDate = DateTime.now();
  String _selectedHourlyView = 'Full Day'; // New state for Hourly view
  final List<String> _resolutions = ['Hourly', 'Daily', 'Weekly', 'Monthly', 'Yearly'];
  final List<String> _hourlyViews = [
    'Full Day',
    '00:00–03:00',
    '03:00–06:00',
    '06:00–09:00',
    '09:00–12:00',
    '12:00–15:00',
    '15:00–18:00',
    '18:00–21:00',
    '21:00–24:00',
  ];

  @override
  void initState() {
    super.initState();
    _logger.i('ReportsScreen initialized with ${widget.csvData.length} data rows');
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _logger.i('Selected date: ${_selectedDate.toString().substring(0, 10)}');
    }
  }

  void _previousDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    });
    _logger.i('Navigated to previous day: ${_selectedDate.toString().substring(0, 10)}');
  }

  void _nextDay() {
    final now = DateTime.now();
    final nextDay = _selectedDate.add(const Duration(days: 1));
    if (nextDay.isBefore(now) || nextDay.isAtSameMomentAs(now)) {
      setState(() {
        _selectedDate = nextDay;
      });
      _logger.i('Navigated to next day: ${_selectedDate.toString().substring(0, 10)}');
    }
  }

  List<Map<String, dynamic>> _processHourlyData() {
    final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    //final endOfDay = startOfDay.add(const Duration(days: 1));
    final startTimestamp = startOfDay.millisecondsSinceEpoch ~/ 1000;
    //final endTimestamp = endOfDay.millisecondsSinceEpoch ~/ 1000;

    // Determine the time window for Hourly view
    int windowStartHour = 0;
    int windowEndHour = 24;
    if (_selectedHourlyView != 'Full Day') {
      final startHour = int.parse(_selectedHourlyView.split('–')[0].split(':')[0]);
      windowStartHour = startHour;
      windowEndHour = startHour + 3;
    }

    final windowStartTimestamp = startTimestamp + (windowStartHour * 3600);
    final windowEndTimestamp = startTimestamp + (windowEndHour * 3600);

    // Create a map for quick lookup by timestamp
    final dataMap = <int, Map<String, dynamic>>{};
    for (var row in widget.csvData) {
      if (row.length < 4) continue;
      try {
        final timestamp = row[0] as int;
        if (timestamp >= windowStartTimestamp && timestamp < windowEndTimestamp) {
          dataMap[timestamp] = {
            'water_flow_rate': row[1] as double,
            'battery_voltage': row[2] as double,
            'tap_on_duration': row[3] as double,
          };
        }
      } catch (e) {
        _logger.e('Error processing row: $row, $e');
      }
    }

    // Generate data for the selected window
    final List<Map<String, dynamic>> hourlyData = [];
    for (int t = windowStartTimestamp; t < windowEndTimestamp; t++) {
      final data = dataMap[t] ?? {
        'water_flow_rate': 0.0,
        'battery_voltage': 0.0,
        'tap_on_duration': 0.0,
      };
      hourlyData.add({
        'timestamp': t,
        'water_flow_rate': data['water_flow_rate'],
        'battery_voltage': data['battery_voltage'],
        'tap_on_duration': data['tap_on_duration'],
      });
    }

    _logger.i('Processed hourly data: ${hourlyData.length} points for $_selectedHourlyView');
    return hourlyData;
  }

  List<Map<String, dynamic>> _processDailyData() {
    final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final startTimestamp = startOfDay.millisecondsSinceEpoch ~/ 1000;
    final endTimestamp = startOfDay.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;

    // Group data by hour (24 buckets)
    final hourlyBuckets = List.generate(24, (_) => <Map<String, dynamic>>[]);
    for (var row in widget.csvData) {
      if (row.length < 4) continue;
      try {
        final timestamp = row[0] as int;
        if (timestamp >= startTimestamp && timestamp < endTimestamp) {
          final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
          final hour = dateTime.hour;
          hourlyBuckets[hour].add({
            'water_flow_rate': row[1] as double,
            'battery_voltage': row[2] as double,
            'tap_on_duration': row[3] as double,
          });
        }
      } catch (e) {
        _logger.e('Error processing row: $row, $e');
      }
    }

    // Aggregate data for each hour
    final List<Map<String, dynamic>> dailyData = [];
    for (int hour = 0; hour < 24; hour++) {
      final bucket = hourlyBuckets[hour];
      double waterFlowRate = 0.0;
      double batteryVoltage = 0.0;
      double tapOnDuration = 0.0;

      if (bucket.isNotEmpty) {
        waterFlowRate = bucket.fold(0.0, (sum, item) => sum + item['water_flow_rate']) / bucket.length;
        batteryVoltage = bucket.fold(0.0, (sum, item) => sum + item['battery_voltage']) / bucket.length;
        tapOnDuration = bucket.fold(0.0, (sum, item) => sum + item['tap_on_duration']);
      }

      dailyData.add({
        'timestamp': startTimestamp + (hour * 3600),
        'water_flow_rate': waterFlowRate,
        'battery_voltage': batteryVoltage,
        'tap_on_duration': tapOnDuration,
        'hour': hour,
      });
    }

    _logger.i('Processed daily data: ${dailyData.length} points');
    return dailyData;
  }

  List<Map<String, dynamic>> _processWeeklyData() {
    final endOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
    final startOfPeriod = endOfDay.subtract(const Duration(days: 6));
    final startTimestamp = startOfPeriod.millisecondsSinceEpoch ~/ 1000;
    final endTimestamp = endOfDay.millisecondsSinceEpoch ~/ 1000;

    // Group data by day (7 buckets)
    final dailyBuckets = List.generate(7, (_) => <Map<String, dynamic>>[]);
    for (var row in widget.csvData) {
      if (row.length < 4) continue;
      try {
        final timestamp = row[0] as int;
        if (timestamp >= startTimestamp && timestamp <= endTimestamp) {
          final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
          final dayDiff = endOfDay.difference(dateTime).inDays;
          if (dayDiff >= 0 && dayDiff < 7) {
            dailyBuckets[6 - dayDiff].add({
              'water_flow_rate': row[1] as double,
              'battery_voltage': row[2] as double,
              'tap_on_duration': row[3] as double,
            });
          }
        }
      } catch (e) {
        _logger.e('Error processing row: $row, $e');
      }
    }

    // Aggregate data for each day
    final List<Map<String, dynamic>> weeklyData = [];
    for (int day = 0; day < 7; day++) {
      final bucket = dailyBuckets[day];
      double waterFlowRate = 0.0;
      double batteryVoltage = 0.0;
      double tapOnDuration = 0.0;

      if (bucket.isNotEmpty) {
        waterFlowRate = bucket.fold(0.0, (sum, item) => sum + item['water_flow_rate']) / bucket.length;
        batteryVoltage = bucket.fold(0.0, (sum, item) => sum + item['battery_voltage']) / bucket.length;
        tapOnDuration = bucket.fold(0.0, (sum, item) => sum + item['tap_on_duration']);
      }

      final dayDate = startOfPeriod.add(Duration(days: day));
      weeklyData.add({
        'timestamp': (dayDate.millisecondsSinceEpoch ~/ 1000),
        'water_flow_rate': waterFlowRate,
        'battery_voltage': batteryVoltage,
        'tap_on_duration': tapOnDuration,
        'date': dayDate,
      });
    }

    _logger.i('Processed weekly data: ${weeklyData.length} points');
    return weeklyData;
  }

  List<Map<String, dynamic>> _processMonthlyData() {
    final endOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
    final startOfPeriod = endOfDay.subtract(const Duration(days: 27)); // Approx 4 weeks
    final startTimestamp = startOfPeriod.millisecondsSinceEpoch ~/ 1000;
    final endTimestamp = endOfDay.millisecondsSinceEpoch ~/ 1000;

    // Group data by week (4 buckets)
    final weeklyBuckets = List.generate(4, (_) => <Map<String, dynamic>>[]);
    for (var row in widget.csvData) {
      if (row.length < 4) continue;
      try {
        final timestamp = row[0] as int;
        if (timestamp >= startTimestamp && timestamp <= endTimestamp) {
          final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
          final dayDiff = endOfDay.difference(dateTime).inDays;
          final weekIndex = (dayDiff / 7).floor();
          if (weekIndex >= 0 && weekIndex < 4) {
            weeklyBuckets[3 - weekIndex].add({
              'water_flow_rate': row[1] as double,
              'battery_voltage': row[2] as double,
              'tap_on_duration': row[3] as double,
            });
          }
        }
      } catch (e) {
        _logger.e('Error processing row: $row, $e');
      }
    }

    // Aggregate data for each week
    final List<Map<String, dynamic>> monthlyData = [];
    for (int week = 0; week < 4; week++) {
      final bucket = weeklyBuckets[week];
      double waterFlowRate = 0.0;
      double batteryVoltage = 0.0;
      double tapOnDuration = 0.0;

      if (bucket.isNotEmpty) {
        waterFlowRate = bucket.fold(0.0, (sum, item) => sum + item['water_flow_rate']) / bucket.length;
        batteryVoltage = bucket.fold(0.0, (sum, item) => sum + item['battery_voltage']) / bucket.length;
        tapOnDuration = bucket.fold(0.0, (sum, item) => sum + item['tap_on_duration']);
      }

      final weekStart = startOfPeriod.add(Duration(days: week * 7));
      monthlyData.add({
        'timestamp': (weekStart.millisecondsSinceEpoch ~/ 1000),
        'water_flow_rate': waterFlowRate,
        'battery_voltage': batteryVoltage,
        'tap_on_duration': tapOnDuration,
        'week_start': weekStart,
      });
    }

    _logger.i('Processed monthly data: ${monthlyData.length} points');
    return monthlyData;
  }

  List<Map<String, dynamic>> _processYearlyData() {
    final endOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
    final startOfPeriod = DateTime(endOfDay.year - 1, endOfDay.month, endOfDay.day + 1);
    final startTimestamp = startOfPeriod.millisecondsSinceEpoch ~/ 1000;
    final endTimestamp = endOfDay.millisecondsSinceEpoch ~/ 1000;

    // Group data by month (12 buckets)
    final monthlyBuckets = List.generate(12, (_) => <Map<String, dynamic>>[]);
    for (var row in widget.csvData) {
      if (row.length < 4) continue;
      try {
        final timestamp = row[0] as int;
        if (timestamp >= startTimestamp && timestamp <= endTimestamp) {
          final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
          final monthsDiff = ((endOfDay.year - dateTime.year) * 12 + endOfDay.month - dateTime.month);
          if (monthsDiff >= 0 && monthsDiff < 12) {
            monthlyBuckets[11 - monthsDiff].add({
              'water_flow_rate': row[1] as double,
              'battery_voltage': row[2] as double,
              'tap_on_duration': row[3] as double,
            });
          }
        }
      } catch (e) {
        _logger.e('Error processing row: $row, $e');
      }
    }

    // Aggregate data for each month
    final List<Map<String, dynamic>> yearlyData = [];
    for (int month = 0; month < 12; month++) {
      final bucket = monthlyBuckets[month];
      double waterFlowRate = 0.0;
      double batteryVoltage = 0.0;
      double tapOnDuration = 0.0;

      if (bucket.isNotEmpty) {
        waterFlowRate = bucket.fold(0.0, (sum, item) => sum + item['water_flow_rate']) / bucket.length;
        batteryVoltage = bucket.fold(0.0, (sum, item) => sum + item['battery_voltage']) / bucket.length;
        tapOnDuration = bucket.fold(0.0, (sum, item) => sum + item['tap_on_duration']);
      }

      final monthDate = startOfPeriod.add(Duration(days: month * 30)); // Approximate
      yearlyData.add({
        'timestamp': (monthDate.millisecondsSinceEpoch ~/ 1000),
        'water_flow_rate': waterFlowRate,
        'battery_voltage': batteryVoltage,
        'tap_on_duration': tapOnDuration,
        'month': monthDate,
      });
    }

    _logger.i('Processed yearly data: ${yearlyData.length} points');
    return yearlyData;
  }

  Widget _buildSingleChart({
    required String title,
    required List<FlSpot> spots,
    required Color color,
    required List<Map<String, dynamic>> data,
    required String xAxisLabel,
    required double interval,
    required String Function(double, TitleMeta) titleFormatter,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          height: 150, // Reduced height for each chart
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: LineChart(
            LineChartData(
              gridData: const FlGridData(show: true),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    getTitlesWidget: (value, meta) {
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          titleFormatter(value, meta),
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                    interval: interval,
                  ),
                  axisNameWidget: Text(xAxisLabel),
                  axisNameSize: 20,
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          value.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: true),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  color: color,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(show: false),
                ),
              ],
              minX: _selectedResolution == 'Hourly' ? 0 : null,
              maxX: _selectedResolution == 'Hourly' ? null : (data.length - 1).toDouble(),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final index = spot.x.toInt();
                      final item = data[index];
                      String label = '';
                      if (_selectedResolution == 'Hourly') {
                        final dateTime = DateTime.fromMillisecondsSinceEpoch((item['timestamp'] * 1000).toInt());
                        label = DateFormat('HH:mm:ss').format(dateTime);
                      } else if (_selectedResolution == 'Daily') {
                        label = '${item['hour']}:00';
                      } else if (_selectedResolution == 'Weekly') {
                        label = DateFormat('MM-dd').format(item['date']);
                      } else if (_selectedResolution == 'Monthly') {
                        label = DateFormat('MM-dd').format(item['week_start']);
                      } else if (_selectedResolution == 'Yearly') {
                        label = DateFormat('MMM yyyy').format(item['month']);
                      }
                      return LineTooltipItem(
                        '$label\n${spot.y}',
                        const TextStyle(color: Colors.white),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChart() {
    List<Map<String, dynamic>> data;
    String xAxisLabel = '';
    double interval = 1;
    String Function(double, TitleMeta) titleFormatter = (value, meta) => value.toString();

    switch (_selectedResolution) {
      case 'Hourly':
        data = _processHourlyData();
        xAxisLabel = 'Time';
        interval = _selectedHourlyView == 'Full Day' ? 3600 : 1800; // Hourly: 1-hour ticks for Full Day, 30-min ticks for 3-hour
        titleFormatter = (value, meta) {
          final baseTimestamp = data.first['timestamp'] as int;
          final dateTime = DateTime.fromMillisecondsSinceEpoch(((baseTimestamp + value) * 1000).toInt());
          return DateFormat('HH:mm').format(dateTime);
        };
        break;
      case 'Daily':
        data = _processDailyData();
        xAxisLabel = 'Hour';
        interval = 1;
        titleFormatter = (value, meta) => '${value.toInt()}:00';
        break;
      case 'Weekly':
        data = _processWeeklyData();
        xAxisLabel = 'Date';
        interval = 1;
        titleFormatter = (value, meta) {
          final date = data[value.toInt()]['date'] as DateTime;
          return DateFormat('MM-dd').format(date);
        };
        break;
      case 'Monthly':
        data = _processMonthlyData();
        xAxisLabel = 'Week Start';
        interval = 1;
        titleFormatter = (value, meta) {
          final date = data[value.toInt()]['week_start'] as DateTime;
          return DateFormat('MM-dd').format(date);
        };
        break;
      case 'Yearly':
        data = _processYearlyData();
        xAxisLabel = 'Month';
        interval = 1;
        titleFormatter = (value, meta) {
          final date = data[value.toInt()]['month'] as DateTime;
          return DateFormat('MMM').format(date);
        };
        break;
      default:
        return const SizedBox();
    }

    if (data.isEmpty) {
      return const Center(child: Text('No data available'));
    }

    final waterFlowSpots = <FlSpot>[];
    final batteryVoltageSpots = <FlSpot>[];
    final tapOnDurationSpots = <FlSpot>[];

    for (int i = 0; i < data.length; i++) {
      final item = data[i];
      if (_selectedResolution == 'Hourly') {
        waterFlowSpots.add(FlSpot((item['timestamp'] - data.first['timestamp']).toDouble(), item['water_flow_rate']));
        batteryVoltageSpots.add(FlSpot((item['timestamp'] - data.first['timestamp']).toDouble(), item['battery_voltage']));
        tapOnDurationSpots.add(FlSpot((item['timestamp'] - data.first['timestamp']).toDouble(), item['tap_on_duration']));
      } else {
        waterFlowSpots.add(FlSpot(i.toDouble(), item['water_flow_rate']));
        batteryVoltageSpots.add(FlSpot(i.toDouble(), item['battery_voltage']));
        tapOnDurationSpots.add(FlSpot(i.toDouble(), item['tap_on_duration']));
      }
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSingleChart(
            title: 'Water Flow Rate',
            spots: waterFlowSpots,
            color: Colors.blue,
            data: data,
            xAxisLabel: xAxisLabel,
            interval: interval,
            titleFormatter: titleFormatter,
          ),
          _buildSingleChart(
            title: 'Battery Voltage',
            spots: batteryVoltageSpots,
            color: Colors.green,
            data: data,
            xAxisLabel: xAxisLabel,
            interval: interval,
            titleFormatter: titleFormatter,
          ),
          _buildSingleChart(
            title: 'Tap On Duration',
            spots: tapOnDurationSpots,
            color: Colors.red,
            data: data,
            xAxisLabel: xAxisLabel,
            interval: interval,
            titleFormatter: titleFormatter,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _previousDay,
                  icon: const Icon(Icons.arrow_left),
                  tooltip: 'Previous Day',
                ),
                const Text('Select Date: '),
                TextButton(
                  onPressed: _selectDate,
                  child: Text(
                    DateFormat('yyyy-MM-dd').format(_selectedDate),
                    style: const TextStyle(fontSize: 16, color: Colors.blue),
                  ),
                ),
                IconButton(
                  onPressed: _nextDay,
                  icon: const Icon(Icons.arrow_right),
                  tooltip: 'Next Day',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: DropdownButton<String>(
              value: _selectedResolution,
              isExpanded: true,
              items: _resolutions.map((String resolution) {
                return DropdownMenuItem<String>(
                  value: resolution,
                  child: Text(resolution),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedResolution = value!;
                  if (_selectedResolution != 'Hourly') {
                    _selectedHourlyView = 'Full Day'; // Reset to Full Day for non-Hourly
                  }
                });
                _logger.i('Resolution changed to: $_selectedResolution');
              },
            ),
          ),
          if (_selectedResolution == 'Hourly')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: DropdownButton<String>(
                value: _selectedHourlyView,
                isExpanded: true,
                items: _hourlyViews.map((String view) {
                  return DropdownMenuItem<String>(
                    value: view,
                    child: Text(view),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedHourlyView = value!;
                  });
                  _logger.i('Hourly view changed to: $_selectedHourlyView');
                },
              ),
            ),
          Expanded(child: _buildChart()),
        ],
      ),
    );
  }
}