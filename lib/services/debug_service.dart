import 'package:logger/logger.dart';
import 'dart:async';
import 'dart:io';
import 'package:intl/intl.dart';

class DebugService {
  static final DebugService _instance = DebugService._internal();
  factory DebugService() => _instance;
  DebugService._internal();

  final Logger _logger = Logger();
  bool _isEnabled = false;
  final List<String> _logBuffer = [];
  static const int _maxBufferSize = 1000;
  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();

  // Getters
  bool get isEnabled => _isEnabled;
  Stream<String> get logStream => _logStreamController.stream;
  List<String> get logBuffer => List.unmodifiable(_logBuffer);

  // Enable/disable debugging
  void enableDebugging() {
    _isEnabled = true;
    _logger.i('Debug logging enabled');
    _addToBuffer('DEBUG: Debug logging enabled');
  }

  void disableDebugging() {
    _isEnabled = false;
    _logger.i('Debug logging disabled');
    _addToBuffer('DEBUG: Debug logging disabled');
  }

  void toggleDebugging() {
    if (_isEnabled) {
      disableDebugging();
    } else {
      enableDebugging();
    }
  }

  // Logging methods
  void log(String message, {String? tag}) {
    if (!_isEnabled) return;

    final timestamp = DateTime.now().toString().substring(11, 19);
    final formattedMessage = tag != null ? '[TAG:$tag] $message' : message;
    final fullMessage = '[$timestamp] $formattedMessage';

    _logger.i(fullMessage);
    _addToBuffer(fullMessage);
  }

  void logData(String data, {String? tag}) {
    if (!_isEnabled) return;
    log('DATA: $data', tag: tag);
  }

  void logCommand(String command, {String? tag}) {
    if (!_isEnabled) return;
    log('CMD: $command', tag: tag);
  }

  void logResponse(String response, {String? tag}) {
    if (!_isEnabled) return;
    log('RESP: $response', tag: tag);
  }

  void logError(String error, {String? tag}) {
    if (!_isEnabled) return;
    log('ERROR: $error', tag: tag);
  }

  void logConnection(String status, {String? tag}) {
    if (!_isEnabled) return;
    log('CONN: $status', tag: tag);
  }

  void logFlow(String status, {String? tag}) {
    if (!_isEnabled) return;
    log('FLOW: $status', tag: tag);
  }

  void logBattery(double voltage, {String? tag}) {
    if (!_isEnabled) return;
    log('BAT: ${voltage.toStringAsFixed(2)}V', tag: tag);
  }

  void logWaterFlow(double flowRate, {String? tag}) {
    if (!_isEnabled) return;
    log('WATER: ${flowRate.toStringAsFixed(2)} L/s', tag: tag);
  }

  void logTapDuration(double duration, {String? tag}) {
    if (!_isEnabled) return;
    log('TAP: ${duration.toStringAsFixed(1)}s', tag: tag);
  }

  void logRawData(List<int> data, {String? tag}) {
    if (!_isEnabled) return;
    final hexString =
        data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(' ');
    log('RAW: $hexString', tag: tag);
  }

  void logParsedData(String data, {String? tag}) {
    if (!_isEnabled) return;
    log('PARSED: $data', tag: tag);
  }

  // Buffer management
  void _addToBuffer(String message) {
    _logBuffer.add(message);
    if (_logBuffer.length > _maxBufferSize) {
      _logBuffer.removeAt(0);
    }
    _logStreamController.add(message);
  }

  void clearBuffer() {
    _logBuffer.clear();
    _logger.i('Debug buffer cleared');
  }

  String getBufferAsString() {
    return _logBuffer.join('\n');
  }

  // Export logs to console
  String exportLogs() {
    final header = '=== Water Monitor Debug Logs ===\n';
    final footer = '\n=== End of Logs ===\n';
    return '$header${getBufferAsString()}$footer';
  }

  // Export logs to file
  Future<Map<String, dynamic>> exportLogsToFile() async {
    try {
      const documentsPath = '/storage/emulated/0/Documents';
      final directory = Directory(documentsPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final timestamp =
          DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final fileName = 'debug_logs_$timestamp.txt';
      final file = File('$documentsPath/$fileName');

      final header = '''=== Water Monitor Debug Logs ===
Generated: ${DateTime.now().toString()}
Total Log Entries: ${_logBuffer.length}
Buffer Size: ${_logBuffer.length}/$_maxBufferSize

''';
      final footer = '\n=== End of Logs ===\n';
      final content = '$header${getBufferAsString()}$footer';

      await file.writeAsString(content);
      final fileSize = await file.length();
      final fileSizeKB = (fileSize / 1024).toStringAsFixed(2);

      _logger.i('Debug logs exported to file: ${file.path} ($fileSizeKB KB)');

      return {
        'success': true,
        'path': file.path,
        'fileName': fileName,
        'fileSize': fileSize,
        'fileSizeKB': fileSizeKB,
        'entryCount': _logBuffer.length,
        'timestamp': DateTime.now().toString(),
      };
    } catch (e) {
      _logger.e('Failed to export debug logs to file: $e');
      return {
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toString(),
      };
    }
  }

  // Performance logging
  void logPerformance(String operation, Duration duration, {String? tag}) {
    if (!_isEnabled) return;
    log('PERF: $operation took ${duration.inMilliseconds}ms', tag: tag);
  }

  // Memory usage logging
  void logMemoryUsage(String context, {String? tag}) {
    if (!_isEnabled) return;
    log('MEM: Buffer size: ${_logBuffer.length}/$_maxBufferSize', tag: tag);
  }

  // Dispose
  void dispose() {
    _logStreamController.close();
    _logger.i('DebugService disposed');
  }
}
