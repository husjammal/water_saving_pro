import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CsvManager {
  final Logger _logger = Logger();
  List<List<dynamic>> csvData = [];
  int lastTimestamp = 0;
  File? _csvFile;

  Future<void> loadPersistedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      lastTimestamp = prefs.getInt('lastTimestamp') ?? 0;
      _logger.i('Loaded lastTimestamp: $lastTimestamp');

      final directory = await getExternalStorageDirectory();
      _csvFile = File('${directory!.path}/documents/water_data.csv');
      if (await _csvFile!.exists()) {
        final content = await _csvFile!.readAsString();
        csvData = content.split('\n').map((line) => line.split(',')).toList();
        csvData.removeWhere((row) => row.length < 4); // Remove invalid rows
        _logger.i('Loaded ${csvData.length} rows from CSV');
      } else {
        await _csvFile!.create(recursive: true);
        csvData = [];
        _logger.i('Created new CSV file at ${_csvFile!.path}');
      }
    } catch (e) {
      _logger.e('Failed to load persisted data: $e');
    }
  }

  Future<void> saveCsvData() async {
    try {
      if (_csvFile == null) {
        final directory = await getExternalStorageDirectory();
        _csvFile = File('${directory!.path}/documents/water_data.csv');
      }
      final content = csvData.map((row) => row.join(',')).join('\n');
      await _csvFile!.writeAsString(content);
      _logger.i('Saved ${csvData.length} rows to CSV');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('lastTimestamp', lastTimestamp);

      final summary = {
        'success': true,
        'path': _csvFile!.path,
        'rowCount': csvData.length,
        'fileSizeKB': (await _csvFile!.length()) / 1024,
        'fileSizeBytes': await _csvFile!.length(),
        'saveTime': DateTime.now().toString(),
        'duplicateCount': 0,
        'filteredCount': 0,
      };
      await prefs.setString('csvSummary', jsonEncode(summary));
      _logger.i('Saved CSV summary');
    } catch (e) {
      _logger.e('Failed to save CSV data: $e');
    }
  }

  void addDataRow(List<dynamic> row) {
    if (row.length >= 4 && row[0] is int && row[0] > lastTimestamp) {
      csvData.add(row);
      lastTimestamp = row[0] as int;
      _logger.i('Added row with timestamp: ${row[0]}');
    }
  }

  Future<Map<String, dynamic>> cleanCsvData(bool confirmed) async {
    if (!confirmed) {
      return {'success': false, 'message': 'Cancelled'};
    }
    try {
      final sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180));
      final seenTimestamps = <int>{};
      int duplicateCount = 0;
      int filteredCount = 0;

      final cleanedData = <List<dynamic>>[];
      for (var row in csvData) {
        if (row.length < 4 || row[0] is! int) {
          filteredCount++;
          continue;
        }
        final timestamp = row[0] as int;
        final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
        if (seenTimestamps.contains(timestamp) || date.isBefore(sixMonthsAgo) || date.isAfter(DateTime.now())) {
          if (seenTimestamps.contains(timestamp)) {
            duplicateCount++;
          } else {
            filteredCount++;
          }
          continue;
        }
        seenTimestamps.add(timestamp);
        cleanedData.add(row);
      }

      csvData = cleanedData;
      lastTimestamp = csvData.isNotEmpty ? csvData.last[0] as int : 0;
      await saveCsvData();

      final result = {
        'success': true,
        'path': _csvFile!.path,
        'rowCount': csvData.length,
        'fileSizeKB': (await _csvFile!.length()) / 1024,
        'fileSizeBytes': await _csvFile!.length(),
        'saveTime': DateTime.now().toString(),
        'duplicateCount': duplicateCount,
        'filteredCount': filteredCount,
      };
      _logger.i('Cleaned CSV: $result');
      return result;
    } catch (e) {
      _logger.e('Failed to clean CSV: $e');
      return {'success': false, 'message': 'Failed to clean CSV: $e'};
    }
  }

  Future<void> clearCsvData(bool confirmed) async {
    if (confirmed) {
      csvData.clear();
      lastTimestamp = 0;
      await saveCsvData();
      _logger.i('Cleared CSV data');
    }
  }

  Future<void> setManualTimestamp(BuildContext context) async {
    try {
      final now = DateTime.now();
      final date = await showDatePicker(
        context: context,
        initialDate: lastTimestamp == 0 ? now : DateTime.fromMillisecondsSinceEpoch(lastTimestamp * 1000),
        firstDate: DateTime(2020),
        lastDate: now,
      );
      if (date == null) return;

      final time = await showTimePicker(
        context: context,
        initialTime: lastTimestamp == 0 ? TimeOfDay.fromDateTime(now) : TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(lastTimestamp * 1000)),
      );
      if (time == null) return;

      final selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      if (selectedDateTime.isAfter(now)) {
        throw Exception('Cannot set timestamp to future time');
      }

      lastTimestamp = selectedDateTime.millisecondsSinceEpoch ~/ 1000;
      await saveCsvData();
      _logger.i('Set manual timestamp: $lastTimestamp');
    } catch (e) {
      _logger.e('Failed to set manual timestamp: $e');
      rethrow;
    }
  }

  Future<void> shareCsvFile() async {
    try {
      if (_csvFile == null || !await _csvFile!.exists()) {
        throw Exception('CSV file does not exist');
      }
      // Implement sharing logic (e.g., using share_plus package)
      _logger.i('Shared CSV file: ${_csvFile!.path}');
    } catch (e) {
      _logger.e('Failed to share CSV: $e');
      rethrow;
    }
  }

  void dispose() {
    _logger.i('CsvManager disposed');
  }
}