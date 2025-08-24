import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:logger/logger.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/data_state_model.dart';
import '../models/connection_state_model.dart';
import '../models/settings_model.dart';
import '../widgets/app_drawer.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final Logger _logger = Logger();
  String _selectedResolution = 'Daily';
  DateTime _selectedDate = DateTime.now();
  String _selectedHourlyView = 'Full Day';
  bool _isSummaryExpanded = true; // State for expansion panel
  bool _isChartFullScreen = false; // NEW: Full screen toggle
  final List<String> _resolutions = [
    'Hourly',
    'Daily',
    'Weekly',
    'Monthly',
    'Yearly'
  ];
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

  // Performance optimization: Cache for processed data
  final Map<String, List<Map<String, dynamic>>> _dataCache = {};
  final String _lastCacheKey = '';
  List<Map<String, dynamic>>? _cachedData;

  // Performance optimization: Cache for chart spots
  final Map<String, Map<String, List<FlSpot>>> _spotsCache = {};

  // Performance optimization: Debounce timer for UI updates
  Timer? _debounceTimer;

  // Calculate report summary based on processed data
  Map<String, dynamic> _calculateReportSummary(
      List<Map<String, dynamic>> data, SettingsModel settingsModel) {
    if (data.isEmpty) {
      return {
        'totalTapDuration': 0.0,
        'avgBatteryVoltage': 0.0,
        'totalWaterUsed': 0.0,
        'waterSavings': 0.0,
        'waterSavingPercentage': 0.0,
        'costSavings': 0.0,
        'dataPoints': 0,
      };
    }

    double totalTapDuration = 0.0;
    double totalBatteryVoltage = 0.0;
    int batteryDataPoints = 0;
    double totalWaterUsed = 0.0;
    double totalWaterSavings = 0.0;
    int dataPoints = 0;

    for (var item in data) {
      double flowRate = item['water_flow_rate'] as double;
      double tapDuration = item['tap_on_duration'] as double;
      double batteryVoltage = item['battery_voltage'] as double;

      totalTapDuration += tapDuration;

      // Only include non-zero battery voltage readings in average
      if (batteryVoltage > 0) {
        totalBatteryVoltage += batteryVoltage;
        batteryDataPoints++;
      }

      // Calculate water used (flow rate * duration)
      double waterUsed = flowRate * tapDuration;
      totalWaterUsed += waterUsed;

      // Only calculate water savings if tap is ON (duration > 0)
      if (tapDuration > 0) {
        double waterSavings =
            settingsModel.calculateWaterSavings(flowRate, tapDuration);
        totalWaterSavings += waterSavings;
      }

      dataPoints++;
    }

    double avgBatteryVoltage =
        batteryDataPoints > 0 ? totalBatteryVoltage / batteryDataPoints : 0.0;
    double waterSavingPercentage =
        totalWaterUsed > 0 ? (totalWaterSavings / totalWaterUsed) * 100 : 0.0;
    double costSavings = settingsModel.calculateCostSavings(totalWaterSavings);

    return {
      'totalTapDuration': totalTapDuration,
      'avgBatteryVoltage': avgBatteryVoltage,
      'totalWaterUsed': totalWaterUsed,
      'waterSavings': totalWaterSavings,
      'waterSavingPercentage': waterSavingPercentage,
      'costSavings': costSavings,
      'dataPoints': dataPoints,
    };
  }

  @override
  void initState() {
    super.initState();
    _logger.i('ReportsScreen initialized');
    // Stop live data when entering reports
    Future.microtask(() async {
      final connectionModel =
          Provider.of<ConnectionStateModel>(context, listen: false);
      if (connectionModel.isConnected) {
        _logger.i('[STOP_LIVE_DATA] Sent from ReportsScreen');
        await connectionModel.writeCommand('STOP_LIVE_DATA');
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _logger.i('ReportsScreen disposed');
    super.dispose();
  }

  // Performance optimization: Generate cache key for current state
  String _generateCacheKey(List<List<dynamic>> csvData) {
    return '${_selectedResolution}_${_selectedDate.millisecondsSinceEpoch}_${_selectedHourlyView}_${csvData.length}';
  }

  // Performance optimization: Get cached data or process and cache
  List<Map<String, dynamic>> _getProcessedData(List<List<dynamic>> csvData) {
    final cacheKey = _generateCacheKey(csvData);

    // Return cached data if available
    if (_dataCache.containsKey(cacheKey)) {
      _logger.d('Using cached data for key: $cacheKey');
      return _dataCache[cacheKey]!;
    }

    // Process data and cache it
    List<Map<String, dynamic>> processedData;
    switch (_selectedResolution) {
      case 'Hourly':
        processedData = _processHourlyData(csvData);
        break;
      case 'Daily':
        processedData = _processDailyData(csvData);
        break;
      case 'Weekly':
        processedData = _processWeeklyData(csvData);
        break;
      case 'Monthly':
        processedData = _processMonthlyData(csvData);
        break;
      case 'Yearly':
        processedData = _processYearlyData(csvData);
        break;
      default:
        processedData = [];
    }

    // Cache the result (limit cache size to prevent memory issues)
    if (_dataCache.length > 10) {
      _dataCache.clear();
    }
    _dataCache[cacheKey] = processedData;
    _logger.d('Cached processed data for key: $cacheKey');

    return processedData;
  }

  // Performance optimization: Get cached chart spots or generate and cache
  Map<String, List<FlSpot>> _getChartSpots(List<Map<String, dynamic>> data) {
    final cacheKey = '${_selectedResolution}_${data.length}';

    if (_spotsCache.containsKey(cacheKey)) {
      _logger.d('Using cached spots for key: $cacheKey');
      return _spotsCache[cacheKey]!;
    }

    final waterFlowSpots = <FlSpot>[];
    final batteryVoltageSpots = <FlSpot>[];
    final tapOnDurationSpots = <FlSpot>[];

    for (int i = 0; i < data.length; i++) {
      final item = data[i];
      if (_selectedResolution == 'Hourly') {
        waterFlowSpots.add(FlSpot(
            (item['timestamp'] - data.first['timestamp']).toDouble(),
            item['water_flow_rate']));
        batteryVoltageSpots.add(FlSpot(
            (item['timestamp'] - data.first['timestamp']).toDouble(),
            item['battery_voltage']));
        tapOnDurationSpots.add(FlSpot(
            (item['timestamp'] - data.first['timestamp']).toDouble(),
            item['tap_on_duration']));
      } else {
        waterFlowSpots.add(FlSpot(i.toDouble(), item['water_flow_rate'] * 60));
        batteryVoltageSpots.add(FlSpot(i.toDouble(), item['battery_voltage']));
        tapOnDurationSpots.add(FlSpot(i.toDouble(), item['tap_on_duration']));
      }
    }

    final spots = {
      'water_flow': waterFlowSpots,
      'battery_voltage': batteryVoltageSpots,
      'tap_on_duration': tapOnDurationSpots,
    };

    // Cache the result
    if (_spotsCache.length > 10) {
      _spotsCache.clear();
    }
    _spotsCache[cacheKey] = spots;
    _logger.d('Cached chart spots for key: $cacheKey');

    return spots;
  }

  // Performance optimization: Clear cache when parameters change
  void _clearCache() {
    _dataCache.clear();
    _spotsCache.clear();
    _logger.d('Cache cleared');
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
      _clearCache(); // Clear cache when date changes
    }
  }

  void _previousDay() {
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
    });
    _logger.i(
        'Navigated to previous day: ${_selectedDate.toString().substring(0, 10)}');
    _clearCache(); // Clear cache when date changes
  }

  void _nextDay() {
    final now = DateTime.now();
    final nextDay = _selectedDate.add(const Duration(days: 1));
    if (nextDay.isBefore(now) || nextDay.isAtSameMomentAs(now)) {
      setState(() {
        _selectedDate = nextDay;
      });
      _logger.i(
          'Navigated to next day: ${_selectedDate.toString().substring(0, 10)}');
      _clearCache(); // Clear cache when date changes
    }
  }

  List<Map<String, dynamic>> _processHourlyData(List<List<dynamic>> csvData) {
    final startOfDay =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final startTimestamp = startOfDay.millisecondsSinceEpoch ~/ 1000;

    int windowStartHour = 0;
    int windowEndHour = 24;
    if (_selectedHourlyView != 'Full Day') {
      final startHour =
          int.parse(_selectedHourlyView.split('–')[0].split(':')[0]);
      windowStartHour = startHour;
      windowEndHour = startHour + 3;
    }

    final windowStartTimestamp = startTimestamp + (windowStartHour * 3600);
    final windowEndTimestamp = startTimestamp + (windowEndHour * 3600);

    // Performance optimization: Pre-filter data to reduce iterations
    final filteredData = csvData.where((row) {
      if (row.length < 4) return false;
      try {
        final timestamp = row[0] as int;
        return timestamp >= windowStartTimestamp &&
            timestamp < windowEndTimestamp;
      } catch (e) {
        return false;
      }
    }).toList();

    final dataMap = <int, Map<String, dynamic>>{};
    for (var row in filteredData) {
      try {
        final timestamp = row[0] as int;
        dataMap[timestamp] = {
          'water_flow_rate': row[1] as double,
          'battery_voltage': row[2] as double,
          'tap_on_duration': row[3] as double,
        };
      } catch (e) {
        _logger.e('Error processing row: $row, $e');
      }
    }

    final List<Map<String, dynamic>> hourlyData = [];
    for (int t = windowStartTimestamp; t < windowEndTimestamp; t++) {
      final data = dataMap[t] ??
          {
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

    _logger.i(
        'Processed hourly data: ${hourlyData.length} points for $_selectedHourlyView (filtered from ${csvData.length} to ${filteredData.length} rows)');
    return hourlyData;
  }

  List<Map<String, dynamic>> _processDailyData(List<List<dynamic>> csvData) {
    final startOfDay =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final startTimestamp = startOfDay.millisecondsSinceEpoch ~/ 1000;
    final endTimestamp =
        startOfDay.add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000;

    // Performance optimization: Pre-filter data to reduce iterations
    final filteredData = csvData.where((row) {
      if (row.length < 4) return false;
      try {
        final timestamp = row[0] as int;
        return timestamp >= startTimestamp && timestamp < endTimestamp;
      } catch (e) {
        return false;
      }
    }).toList();

    final hourlyBuckets = List.generate(24, (_) => <Map<String, dynamic>>[]);
    for (var row in filteredData) {
      try {
        final timestamp = row[0] as int;
        final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        final hour = dateTime.hour;
        hourlyBuckets[hour].add({
          'water_flow_rate': row[1] as double,
          'battery_voltage': row[2] as double,
          'tap_on_duration': row[3] as double,
        });
      } catch (e) {
        _logger.e('Error processing row: $row, $e');
      }
    }

    final List<Map<String, dynamic>> dailyData = [];
    for (int hour = 0; hour < 24; hour++) {
      final bucket = hourlyBuckets[hour];
      double waterFlowRate = 0.0;
      double batteryVoltage = 0.0;
      double tapOnDuration = 0.0;

      if (bucket.isNotEmpty) {
        // Performance optimization: Single-pass aggregation
        double waterSum = 0.0;
        double batterySum = 0.0;
        double tapSum = 0.0;
        for (final item in bucket) {
          waterSum += item['water_flow_rate'];
          batterySum += item['battery_voltage'];
          tapSum += item['tap_on_duration'];
        }
        waterFlowRate = waterSum / bucket.length;
        batteryVoltage = batterySum / bucket.length;
        tapOnDuration = tapSum;
      }

      dailyData.add({
        'timestamp': startTimestamp + (hour * 3600),
        'water_flow_rate': waterFlowRate,
        'battery_voltage': batteryVoltage,
        'tap_on_duration': tapOnDuration,
        'hour': hour,
      });
    }

    _logger.i(
        'Processed daily data: ${dailyData.length} points (filtered from ${csvData.length} to ${filteredData.length} rows)');
    return dailyData;
  }

  List<Map<String, dynamic>> _processWeeklyData(List<List<dynamic>> csvData) {
    final endOfDay = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
    final startOfPeriod = endOfDay.subtract(const Duration(days: 6));
    final startTimestamp = startOfPeriod.millisecondsSinceEpoch ~/ 1000;
    final endTimestamp = endOfDay.millisecondsSinceEpoch ~/ 1000;

    final dailyBuckets = List.generate(7, (_) => <Map<String, dynamic>>[]);
    for (var row in csvData) {
      if (row.length < 4) continue;
      try {
        final timestamp = row[0] as int;
        if (timestamp >= startTimestamp && timestamp <= endTimestamp) {
          final dateTime =
              DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
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

    final List<Map<String, dynamic>> weeklyData = [];
    for (int day = 0; day < 7; day++) {
      final bucket = dailyBuckets[day];
      double waterFlowRate = 0.0;
      double batteryVoltage = 0.0;
      double tapOnDuration = 0.0;

      if (bucket.isNotEmpty) {
        waterFlowRate =
            bucket.fold(0.0, (sum, item) => sum + item['water_flow_rate']) /
                bucket.length;
        batteryVoltage =
            bucket.fold(0.0, (sum, item) => sum + item['battery_voltage']) /
                bucket.length;
        tapOnDuration =
            bucket.fold(0.0, (sum, item) => sum + item['tap_on_duration']);
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

  List<Map<String, dynamic>> _processMonthlyData(List<List<dynamic>> csvData) {
    final endOfDay = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
    final startOfPeriod = endOfDay.subtract(const Duration(days: 27));
    final startTimestamp = startOfPeriod.millisecondsSinceEpoch ~/ 1000;
    final endTimestamp = endOfDay.millisecondsSinceEpoch ~/ 1000;

    final weeklyBuckets = List.generate(4, (_) => <Map<String, dynamic>>[]);
    for (var row in csvData) {
      if (row.length < 4) continue;
      try {
        final timestamp = row[0] as int;
        if (timestamp >= startTimestamp && timestamp <= endTimestamp) {
          final dateTime =
              DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
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

    final List<Map<String, dynamic>> monthlyData = [];
    for (int week = 0; week < 4; week++) {
      final bucket = weeklyBuckets[week];
      double waterFlowRate = 0.0;
      double batteryVoltage = 0.0;
      double tapOnDuration = 0.0;

      if (bucket.isNotEmpty) {
        waterFlowRate =
            bucket.fold(0.0, (sum, item) => sum + item['water_flow_rate']) /
                bucket.length;
        batteryVoltage =
            bucket.fold(0.0, (sum, item) => sum + item['battery_voltage']) /
                bucket.length;
        tapOnDuration =
            bucket.fold(0.0, (sum, item) => sum + item['tap_on_duration']);
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

  List<Map<String, dynamic>> _processYearlyData(List<List<dynamic>> csvData) {
    final endOfDay = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59);
    final startOfPeriod =
        DateTime(endOfDay.year - 1, endOfDay.month, endOfDay.day + 1);
    final startTimestamp = startOfPeriod.millisecondsSinceEpoch ~/ 1000;
    final endTimestamp = endOfDay.millisecondsSinceEpoch ~/ 1000;

    final monthlyBuckets = List.generate(12, (_) => <Map<String, dynamic>>[]);
    for (var row in csvData) {
      if (row.length < 4) continue;
      try {
        final timestamp = row[0] as int;
        if (timestamp >= startTimestamp && timestamp <= endTimestamp) {
          final dateTime =
              DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
          final monthsDiff = ((endOfDay.year - dateTime.year) * 12 +
              endOfDay.month -
              dateTime.month);
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

    final List<Map<String, dynamic>> yearlyData = [];
    for (int month = 0; month < 12; month++) {
      final bucket = monthlyBuckets[month];
      double waterFlowRate = 0.0;
      double batteryVoltage = 0.0;
      double tapOnDuration = 0.0;

      if (bucket.isNotEmpty) {
        waterFlowRate =
            bucket.fold(0.0, (sum, item) => sum + item['water_flow_rate']) /
                bucket.length;
        batteryVoltage =
            bucket.fold(0.0, (sum, item) => sum + item['battery_voltage']) /
                bucket.length;
        tapOnDuration =
            bucket.fold(0.0, (sum, item) => sum + item['tap_on_duration']);
      }

      final monthDate = startOfPeriod.add(Duration(days: month * 30));
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
    String? subtitle,
    required List<FlSpot> spots,
    required Color color,
    required List<Map<String, dynamic>> data,
    required String xAxisLabel,
    required double interval,
    required String Function(double, TitleMeta) titleFormatter,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E6ED)),
      ),
      child: Column(
        children: [
          // Enhanced Header
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Enhanced Chart
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            child: LineChart(
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
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            titleFormatter(value, meta),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF7F8C8D),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                      interval: interval,
                    ),
                    axisNameWidget: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        xAxisLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7F8C8D),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
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
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF7F8C8D),
                              fontWeight: FontWeight.w500,
                            ),
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
                    spots: spots,
                    isCurved: true,
                    color: color,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: color,
                          strokeWidth: 2,
                          strokeColor: Colors.white,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withOpacity(0.1),
                    ),
                  ),
                ],
                minX: _selectedResolution == 'Hourly' ? 0 : null,
                maxX: _selectedResolution == 'Hourly'
                    ? null
                    : (data.length - 1).toDouble(),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots
                          .map((spot) {
                            final index = spot.x.toInt();
                            if (index >= 0 && index < data.length) {
                              final item = data[index];
                              String label = '';
                              if (_selectedResolution == 'Hourly') {
                                final dateTime =
                                    DateTime.fromMillisecondsSinceEpoch(
                                        (item['timestamp'] * 1000).toInt());
                                label = DateFormat('HH:mm:ss').format(dateTime);
                              } else if (_selectedResolution == 'Daily') {
                                label = '${item['hour']}:00';
                              } else if (_selectedResolution == 'Weekly') {
                                label =
                                    DateFormat('MM-dd').format(item['date']);
                              } else if (_selectedResolution == 'Monthly') {
                                label = DateFormat('MM-dd')
                                    .format(item['week_start']);
                              } else if (_selectedResolution == 'Yearly') {
                                label = DateFormat('MMM yyyy')
                                    .format(item['month']);
                              }
                              return LineTooltipItem(
                                '$label\n${spot.y.toStringAsFixed(2)}',
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            }
                            return null;
                          })
                          .where((item) => item != null)
                          .toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<List<dynamic>> csvData) {
    // Performance optimization: Use cached data
    final data = _getProcessedData(csvData);

    if (data.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No data available',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a different date or resolution',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    String xAxisLabel = '';
    double interval = 1;
    String Function(double, TitleMeta) titleFormatter =
        (value, meta) => value.toString();

    switch (_selectedResolution) {
      case 'Hourly':
        xAxisLabel = 'Time';
        interval = _selectedHourlyView == 'Full Day' ? 3600 : 1800;
        titleFormatter = (value, meta) {
          final baseTimestamp = data.first['timestamp'] as int;
          final dateTime = DateTime.fromMillisecondsSinceEpoch(
              ((baseTimestamp + value) * 1000).toInt());
          return DateFormat('HH:mm').format(dateTime);
        };
        break;
      case 'Daily':
        xAxisLabel = 'Hour';
        interval = 1;
        titleFormatter = (value, meta) => '${value.toInt()}:00';
        break;
      case 'Weekly':
        xAxisLabel = 'Date';
        interval = 1;
        titleFormatter = (value, meta) {
          final date = data[value.toInt()]['date'] as DateTime;
          return DateFormat('MM-dd').format(date);
        };
        break;
      case 'Monthly':
        xAxisLabel = 'Week Start';
        interval = 1;
        titleFormatter = (value, meta) {
          final date = data[value.toInt()]['week_start'] as DateTime;
          return DateFormat('MM-dd').format(date);
        };
        break;
      case 'Yearly':
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

    // Performance optimization: Use cached chart spots
    final spots = _getChartSpots(data);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildSingleChart(
            title: 'Water Flow Rate (L/min)',
            subtitle: 'Liters per minute',
            spots: spots['water_flow']!,
            color: const Color(0xFF2196F3),
            data: data,
            xAxisLabel: xAxisLabel,
            interval: interval,
            titleFormatter: titleFormatter,
          ),
          const SizedBox(height: 16),
          _buildSingleChart(
            title: 'Battery Voltage',
            subtitle: 'Volts',
            spots: spots['battery_voltage']!,
            color: const Color(0xFF4CAF50),
            data: data,
            xAxisLabel: xAxisLabel,
            interval: interval,
            titleFormatter: titleFormatter,
          ),
          const SizedBox(height: 16),
          _buildSingleChart(
            title: 'Tap On Duration',
            subtitle: 'Seconds',
            spots: spots['tap_on_duration']!,
            color: const Color(0xFFF44336),
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
    return Consumer<DataStateModel>(
      builder: (context, dataModel, child) {
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
              'Reports',
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
          body: Column(
            children: [
              if (!_isChartFullScreen) ...[
                // Compact Date Selection Card
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Text(
                          'Date:',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: _previousDay,
                          icon: const Icon(
                            Icons.arrow_back_ios,
                            color: Color(0xFF1E5979),
                            size: 18,
                          ),
                          tooltip: 'Previous Day',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        Expanded(
                          child: TextButton(
                            onPressed: _selectDate,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                            ),
                            child: Text(
                              DateFormat('MMM dd, yyyy').format(_selectedDate),
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF1E5979),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _nextDay,
                          icon: const Icon(
                            Icons.arrow_forward_ios,
                            color: Color(0xFF1E5979),
                            size: 18,
                          ),
                          tooltip: 'Next Day',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                ),
                // Compact Controls Card
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        // Resolution Row
                        Row(
                          children: [
                            const Text(
                              'Resolution:',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                height: 36,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: const Color(0xFFE0E6ED)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedResolution,
                                    isExpanded: true,
                                    icon: const Icon(
                                      Icons.keyboard_arrow_down,
                                      color: Color(0xFF1E5979),
                                      size: 18,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    items:
                                        _resolutions.map((String resolution) {
                                      return DropdownMenuItem<String>(
                                        value: resolution,
                                        child: Text(
                                          resolution,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        _selectedResolution = value!;
                                        if (_selectedResolution != 'Hourly') {
                                          _selectedHourlyView = 'Full Day';
                                        }
                                      });
                                      _logger.i(
                                          'Resolution changed to: $_selectedResolution');
                                      _clearCache();
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Hourly View Row (when applicable)
                        if (_selectedResolution == 'Hourly') ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text(
                                'Window:',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  height: 36,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: const Color(0xFFE0E6ED)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedHourlyView,
                                      isExpanded: true,
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down,
                                        color: Color(0xFF1E5979),
                                        size: 18,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      items: _hourlyViews.map((String view) {
                                        return DropdownMenuItem<String>(
                                          value: view,
                                          child: Text(
                                            view,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedHourlyView = value!;
                                        });
                                        _logger.i(
                                            'Hourly view changed to: $_selectedHourlyView');
                                        _clearCache();
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Report Summary Expansion Panel
                Consumer<SettingsModel>(
                  builder: (context, settingsModel, child) {
                    final data = _getProcessedData(dataModel.csvData);
                    final summary =
                        _calculateReportSummary(data, settingsModel);

                    return Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ExpansionPanelList(
                        elevation: 0,
                        expandedHeaderPadding: EdgeInsets.zero,
                        expansionCallback: (panelIndex, isExpanded) {
                          setState(() {
                            _isSummaryExpanded = !_isSummaryExpanded;
                          });
                        },
                        children: [
                          ExpansionPanel(
                            headerBuilder: (context, isExpanded) {
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E5979)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        Icons.analytics,
                                        color: Color(0xFF1E5979),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'Report Summary',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF2C3E50),
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF1E5979)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '${summary['dataPoints']} points',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1E5979),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            body: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildSummaryItem(
                                          icon: Icons.touch_app,
                                          label: 'Total Tap Duration',
                                          value:
                                              '${summary['totalTapDuration'].toStringAsFixed(1)}s',
                                          color: const Color(0xFFF44336),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildSummaryItem(
                                          icon: Icons.battery_full,
                                          label: 'Avg Battery',
                                          value:
                                              '${summary['avgBatteryVoltage'].toStringAsFixed(2)}V',
                                          color: const Color(0xFF4CAF50),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildSummaryItem(
                                          icon: Icons.water_drop,
                                          label: 'Water Used',
                                          value:
                                              '${summary['totalWaterUsed'].toStringAsFixed(2)}L',
                                          color: const Color(0xFF2196F3),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildSummaryItem(
                                          icon: Icons.savings,
                                          label: 'Water Saved',
                                          value:
                                              '${summary['waterSavings'].toStringAsFixed(2)}L',
                                          color: const Color(0xFF00BCD4),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildSummaryItem(
                                          icon: Icons.percent,
                                          label: 'Saving %',
                                          value:
                                              '${summary['waterSavingPercentage'].toStringAsFixed(1)}%',
                                          color: const Color(0xFF9C27B0),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: _buildSummaryItem(
                                          icon: Icons.attach_money,
                                          label: 'Cost Saved',
                                          value:
                                              '\$${summary['costSavings'].toStringAsFixed(2)}',
                                          color: const Color(0xFF4CAF50),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
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
                                          size: 14,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Max flow: ${settingsModel.maxFlowRate.toStringAsFixed(1)} L/s • Price: \$${settingsModel.unitPrice.toStringAsFixed(2)}/L',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF4CAF50),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            isExpanded: _isSummaryExpanded,
                            canTapOnHeader: true,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              // Charts Container with Flexible Height
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(16),
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
                    children: [
                      // Charts Header
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E5979).withOpacity(0.05),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E5979).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.show_chart,
                                color: Color(0xFF1E5979),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Historical Charts',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2C3E50),
                                ),
                              ),
                            ),
                            // Full Screen Toggle Button
                            IconButton(
                              icon: Icon(_isChartFullScreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen),
                              tooltip: _isChartFullScreen
                                  ? 'Exit Full Screen'
                                  : 'Full Screen',
                              onPressed: () {
                                setState(() {
                                  _isChartFullScreen = !_isChartFullScreen;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      // Charts Content with Flexible Height
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          child: SingleChildScrollView(
                            child: _buildChart(dataModel.csvData),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
