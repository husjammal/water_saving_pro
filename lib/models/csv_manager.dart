import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

class CsvManager {
  final Logger _logger = Logger();
  List<List<dynamic>> _csvData = [];
  int _lastTimestamp = 0;

  List<List<dynamic>> get csvData => _csvData;
  int get lastTimestamp => _lastTimestamp;

  Future<void> loadPersistedData() async {
    await loadLastTimestamp();
    await loadCsvData();
  }

  Future<void> loadCsvData() async {
    try {
      const documentsPath = '/storage/emulated/0/Documents';
      final file = File('$documentsPath/water_data.csv');
      if (await file.exists()) {
        final csvString = await file.readAsString();
        if (csvString.trim().isEmpty) {
          _logger.i('CSV file is empty');
          return;
        }
        final result = await compute(_parseCsv, csvString);
        _csvData = result['data'];
        _lastTimestamp = result['lastTimestamp'];
        _logger.i('Loaded ${_csvData.length} records from CSV, lastTimestamp: $_lastTimestamp');
      } else {
        _logger.i('CSV file does not exist');
      }
    } catch (e) {
      _logger.e('Failed to load CSV: $e');
      rethrow;
    }
  }

  Future<void> loadLastTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastTimestamp = prefs.getInt('lastTimestamp') ?? 0;
      _logger.i('Loaded lastTimestamp: $_lastTimestamp');
    } catch (e) {
      _logger.e('Failed to load last timestamp: $e');
      _lastTimestamp = 0;
      rethrow;
    }
  }

  Future<void> saveLastTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('lastTimestamp', _lastTimestamp);
      _logger.i('Saved lastTimestamp: $_lastTimestamp');
    } catch (e) {
      _logger.e('Failed to save last timestamp: $e');
      rethrow;
    }
  }

  Future<void> saveCsvSummary(Map<String, dynamic> result) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('csvSummary', jsonEncode(result));
      _logger.i('Saved CSV summary: $result');
    } catch (e) {
      _logger.e('Failed to save CSV summary: $e');
    }
  }

  static Map<String, dynamic> _parseCsv(String csvString) {
    final csvList = const CsvToListConverter(
      eol: '\n',
      fieldDelimiter: ',',
    ).convert(csvString);
    if (csvList.isEmpty || (csvList.length == 1 && csvList[0].join(',').startsWith('timestamp'))) {
      return {'data': [], 'lastTimestamp': 0};
    }
    final data = csvList
        .skip(1)
        .map((row) {
      if (row.length >= 4) {
        try {
          int timestamp = int.parse(row[0].toString().trim());
          double flowRate = double.parse(row[1].toString().trim());
          double batteryVoltage = double.parse(row[2].toString().trim());
          double tapOnDuration = double.parse(row[3].toString().trim());
          return [timestamp, flowRate, batteryVoltage, tapOnDuration];
        } catch (e) {
          print('Invalid row: $row, Error: $e');
          return null;
        }
      }
      return null;
    })
        .where((row) => row != null)
        .cast<List<dynamic>>()
        .toList();
    int lastTimestamp = data.isNotEmpty
        ? data.map((row) => row[0] as int).reduce((a, b) => a > b ? a : b)
        : 0;
    return {'data': data, 'lastTimestamp': lastTimestamp};
  }

  Map<String, dynamic> processCsvData() {
    int originalCount = _csvData.length;

    final now = DateTime.now();
    final sixMonthsAgo = now.subtract(const Duration(days: 182));
    final currentTimestamp = now.millisecondsSinceEpoch ~/ 1000;
    final sixMonthsAgoTimestamp = sixMonthsAgo.millisecondsSinceEpoch ~/ 1000;

    _csvData = _csvData.where((row) {
      int timestamp = row[0] as int;
      return timestamp >= sixMonthsAgoTimestamp && timestamp <= currentTimestamp;
    }).toList();

    int filteredCount = originalCount - _csvData.length;
    _logger.i('Filtered $filteredCount rows (older than 6 months or future timestamps)');

    final uniqueRows = <String, List<dynamic>>{};
    for (var row in _csvData) {
      uniqueRows[row.join(',')] = row;
    }
    _csvData = uniqueRows.values.toList();
    int duplicateCount = originalCount - filteredCount - _csvData.length;
    _logger.i('Removed $duplicateCount duplicate rows, unique rows: ${_csvData.length}');

    _csvData.sort((a, b) => (a[0] as int).compareTo(b[0] as int));
    _logger.i('Sorted ${_csvData.length} rows by timestamp');

    return {
      'duplicateCount': duplicateCount,
      'filteredCount': filteredCount,
      'rowCount': _csvData.length,
    };
  }

  Future<void> saveCsvData() async {
    try {
      const documentsPath = '/storage/emulated/0/Documents';
      final directory = Directory(documentsPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final file = File('$documentsPath/water_data.csv');

      final result = processCsvData();

      final sink = file.openWrite();
      sink.write('timestamp,water_flow_rate,battery_voltage,tap_on_duration\n');
      for (var row in _csvData) {
        sink.write('${row.join(',')}\n');
      }
      await sink.flush();
      await sink.close();

      final fileSize = await file.length();
      final saveTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final fileSizeKB = (fileSize / 1024).toStringAsFixed(2);

      _lastTimestamp = _csvData.isNotEmpty
          ? _csvData.map((row) => row[0] as int).reduce((a, b) => a > b ? a : b)
          : 0;
      await saveLastTimestamp();

      _logger.i(
          'Saved CSV file: '
              'Path: ${file.path}, '
              'Rows: ${result['rowCount']}, '
              'Size: $fileSizeKB KB ($fileSize bytes), '
              'Saved at: $saveTime, '
              'Duplicates removed: ${result['duplicateCount']}, '
              'Filtered rows: ${result['filteredCount']}');

      final summary = {
        'success': true,
        'path': file.path,
        'rowCount': result['rowCount'],
        'fileSizeKB': fileSizeKB,
        'fileSizeBytes': fileSize,
        'saveTime': saveTime,
        'duplicateCount': result['duplicateCount'],
        'filteredCount': result['filteredCount'],
      };
      await saveCsvSummary(summary);
    } catch (e) {
      _logger.e('Error saving CSV: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> cleanCsvData(bool confirmed) async {
    if (!confirmed) {
      _logger.i('CSV cleaning cancelled by user');
      return {
        'success': false,
        'message': 'CSV cleaning was cancelled',
      };
    }

    try {
      const documentsPath = '/storage/emulated/0/Documents';
      final file = File('$documentsPath/water_data.csv');

      await loadCsvData();

      if (!await file.exists() || _csvData.isEmpty) {
        _logger.i('No data to clean: File does not exist or is empty');
        return {
          'success': false,
          'message': 'No data available to clean',
        };
      }

      final result = processCsvData();

      final sink = file.openWrite();
      sink.write('timestamp,water_flow_rate,battery_voltage,tap_on_duration\n');
      for (var row in _csvData) {
        sink.write('${row.join(',')}\n');
      }
      await sink.flush();
      await sink.close();

      final fileSize = await file.length();
      final saveTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final fileSizeKB = (fileSize / 1024).toStringAsFixed(2);

      _lastTimestamp = _csvData.isNotEmpty
          ? _csvData.map((row) => row[0] as int).reduce((a, b) => a > b ? a : b)
          : 0;
      await saveLastTimestamp();

      final summary = {
        'success': true,
        'path': file.path,
        'rowCount': result['rowCount'],
        'fileSizeKB': fileSizeKB,
        'fileSizeBytes': fileSize,
        'saveTime': saveTime,
        'duplicateCount': result['duplicateCount'],
        'filteredCount': result['filteredCount'],
      };

      _logger.i(
          'Cleaned CSV file: '
              'Path: ${file.path}, '
              'Rows: ${result['rowCount']}, '
              'Size: $fileSizeKB KB ($fileSize bytes), '
              'Saved at: $saveTime, '
              'Duplicates removed: ${result['duplicateCount']}, '
              'Filtered rows: ${result['filteredCount']}');

      await saveCsvSummary(summary);
      return summary;
    } catch (e) {
      _logger.e('Error cleaning CSV: $e');
      return {
        'success': false,
        'message': 'Failed to clean CSV: $e',
      };
    }
  }

  Future<void> clearCsvData(bool confirmed) async {
    if (!confirmed) {
      _logger.i('CSV clearing cancelled by user');
      return;
    }

    try {
      final file = File('/storage/emulated/0/Documents/water_data.csv');
      if (await file.exists()) {
        await file.delete();
        _csvData = [];
        _lastTimestamp = 0;
        await saveLastTimestamp();
        await saveCsvSummary({
          'success': false,
          'message': 'CSV file cleared',
        });
        _logger.i('Cleared CSV data, reset lastTimestamp to 0');
      } else {
        _logger.i('No CSV file to clear');
      }
    } catch (e) {
      _logger.e('Error clearing CSV: $e');
      rethrow;
    }
  }

  Future<void> setManualTimestamp(BuildContext context) async {
    _logger.i('Starting setManualTimestamp');
    final now = DateTime.now();
    final firstDate = DateTime(2020);
    final lastDate = now;

    DateTime initialDate;
    if (_lastTimestamp == 0) {
      initialDate = lastDate;
      _logger.d('No last timestamp, setting initialDate to lastDate: $lastDate');
    } else {
      final timestampDate = DateTime.fromMillisecondsSinceEpoch(_lastTimestamp * 1000);
      if (timestampDate.isAfter(lastDate) || timestampDate.isBefore(firstDate)) {
        _logger.w('Invalid lastTimestamp: $_lastTimestamp, results in $timestampDate, setting initialDate to lastDate: $lastDate');
        initialDate = lastDate;
      } else {
        initialDate = timestampDate;
        _logger.d('Valid lastTimestamp: $_lastTimestamp, setting initialDate to $initialDate');
      }
    }

    DateTime? date;
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      _logger.d('Showing date picker with initialDate: $initialDate');
      date = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
      );
      _logger.d('Date picker result: $date');
    } catch (e) {
      _logger.e('Failed to show date picker: $e');
      rethrow;
    }

    if (date == null) {
      _logger.i('Date picker cancelled');
      return;
    }

    TimeOfDay? time;
    try {
      _logger.d('Showing time picker');
      time = await showTimePicker(
        context: context,
        initialTime: _lastTimestamp == 0
            ? TimeOfDay.fromDateTime(now)
            : TimeOfDay.fromDateTime(
            DateTime.fromMillisecondsSinceEpoch(_lastTimestamp * 1000)),
      );
      _logger.d('Time picker result: $time');
    } catch (e) {
      _logger.e('Failed to show time picker: $e');
      rethrow;
    }

    if (time == null) {
      _logger.i('Time picker cancelled');
      return;
    }

    final selectedDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    final nowTruncated = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    final selectedTruncated = DateTime(
      selectedDateTime.year,
      selectedDateTime.month,
      selectedDateTime.day,
      selectedDateTime.hour,
      selectedDateTime.minute,
    );

    if (selectedTruncated.isAfter(nowTruncated)) {
      _logger.w('Attempted to set future timestamp: $selectedDateTime');
      throw Exception('Cannot set timestamp to future time');
    }

    _lastTimestamp = selectedDateTime.millisecondsSinceEpoch ~/ 1000;
    _logger.i('Set lastTimestamp to: $_lastTimestamp');
    await saveLastTimestamp();
  }

  Future<void> shareCsvFile() async {
    try {
      const documentsPath = '/storage/emulated/0/Documents';
      final file = File('$documentsPath/water_data.csv');
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: 'Water Data CSV',
          text: 'Sharing water_data.csv from Water Monitor App',
        );
        _logger.i('Share initiated for ${file.path}');
      } else {
        _logger.w('No CSV file found to share');
        throw Exception('No CSV file found to share');
      }
    } catch (e) {
      _logger.e('Failed to share CSV: $e');
      rethrow;
    }
  }

  void addDataRow(List<dynamic> row) {
    _logger.d('Adding row to csvData: $row');
    _csvData.add(row);
  }

  void dispose() {
    _logger.i('CsvManager disposed');
  }
}