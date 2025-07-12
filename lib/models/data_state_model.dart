import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class DataStateModel extends ChangeNotifier {
  final Logger _logger = Logger();
  List<List<dynamic>> _csvData = [];
  int _lastTimestamp = 0;
  Map<String, dynamic>? _csvSummary;

  List<List<dynamic>> get csvData => _csvData;
  int get lastTimestamp => _lastTimestamp;
  Map<String, dynamic>? get csvSummary => _csvSummary;

  Future<void> loadPersistedData() async {
    await _loadLastTimestamp();
    await _loadCsvData();
    await _loadCsvSummary();
    notifyListeners();
  }

  Future<void> _loadCsvData() async {
    await loadDataFromFile('/storage/emulated/0/Documents/water_data.csv');
  }

  Future<void> loadDataFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final csvString = await file.readAsString();
        await loadDataFromString(csvString);
        _logger.i('Loaded data from CSV file: $filePath');
      } else {
        _logger.i('No CSV file found at: $filePath');
      }
    } catch (e) {
      _logger.e('Failed to load CSV from $filePath: $e');
    }
    notifyListeners();
  }

  Future<void> loadDataFromString(String csvString) async {
    try {
      if (csvString.trim().isEmpty) {
        _logger.i('CSV string is empty');
        return;
      }
      final csvList = const CsvToListConverter(
        eol: '\n',
        fieldDelimiter: ',',
      ).convert(csvString);
      if (csvList.isEmpty ||
          (csvList.length == 1 &&
              csvList[0].join(',').startsWith('timestamp'))) {
        _csvData = [];
        return;
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
                _logger.e('Invalid row: $row, Error: $e');
                return null;
              }
            }
            return null;
          })
          .where((row) => row != null)
          .cast<List<dynamic>>()
          .toList();
      _csvData = data;
      if (_csvData.isNotEmpty) {
        _lastTimestamp = _csvData
            .map((row) => row[0] as int)
            .reduce((a, b) => a > b ? a : b);
        await _saveLastTimestamp();
      }
      _logger.i('Loaded ${_csvData.length} records from CSV string');
    } catch (e) {
      _logger.e('Failed to load CSV from string: $e');
    }
    notifyListeners();
  }

  Future<void> _loadLastTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastTimestamp = prefs.getInt('lastTimestamp') ?? 0;
      _logger.i('Loaded lastTimestamp: $_lastTimestamp');
    } catch (e) {
      _logger.e('Failed to load last timestamp: $e');
      _lastTimestamp = 0;
    }
    notifyListeners();
  }

  Future<void> _loadCsvSummary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final summaryJson = prefs.getString('csvSummary');
      if (summaryJson != null) {
        _csvSummary = jsonDecode(summaryJson);
      }
    } catch (e) {
      _logger.e('Failed to load CSV summary: $e');
    }
    notifyListeners();
  }

  Future<void> updateCsvData(List<List<dynamic>> newData) async {
    _csvData = newData;
    if (_csvData.isNotEmpty) {
      _lastTimestamp =
          _csvData.map((row) => row[0] as int).reduce((a, b) => a > b ? a : b);
      await _saveLastTimestamp();
    }
    notifyListeners();
  }

  Future<void> updateLastTimestamp(int timestamp) async {
    _lastTimestamp = timestamp;
    await _saveLastTimestamp();
    notifyListeners();
  }

  Future<void> updateCsvSummary(Map<String, dynamic> summary) async {
    _csvSummary = summary;
    await _saveCsvSummary();
    notifyListeners();
  }

  Future<void> clearCsvData() async {
    _csvData = [];
    _lastTimestamp = 0;
    _csvSummary = {'success': true, 'message': 'CSV file cleared'};
    await _saveLastTimestamp();
    await _saveCsvSummary();
    notifyListeners();
  }

  Future<void> _saveLastTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('lastTimestamp', _lastTimestamp);
      _logger.i('Saved lastTimestamp: $_lastTimestamp');
    } catch (e) {
      _logger.e('Failed to save last timestamp: $e');
    }
  }

  Future<void> _saveCsvSummary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('csvSummary', jsonEncode(_csvSummary));
      _logger.i('Saved CSV summary: $_csvSummary');
    } catch (e) {
      _logger.e('Failed to save CSV summary: $e');
    }
  }

  @override
  void dispose() {
    _logger.i('DataStateModel disposed');
    super.dispose();
  }
}
