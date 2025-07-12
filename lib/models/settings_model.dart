import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

class SettingsModel extends ChangeNotifier {
  final Logger _logger = Logger();

  // Default values
  double _maxFlowRate = 2.0; // L/s
  double _unitPrice = 1.0; // USD per liter

  // Getters
  double get maxFlowRate => _maxFlowRate;
  double get unitPrice => _unitPrice;

  SettingsModel() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _maxFlowRate = prefs.getDouble('maxFlowRate') ?? 2.0;
      _unitPrice = prefs.getDouble('unitPrice') ?? 1.0;
      _logger.i(
          'Loaded settings: maxFlowRate=$_maxFlowRate, unitPrice=$_unitPrice');
      notifyListeners();
    } catch (e) {
      _logger.e('Failed to load settings: $e');
    }
  }

  Future<void> updateMaxFlowRate(double value) async {
    if (value != _maxFlowRate) {
      _maxFlowRate = value;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('maxFlowRate', value);
        _logger.i('Updated maxFlowRate to: $value');
        notifyListeners();
      } catch (e) {
        _logger.e('Failed to save maxFlowRate: $e');
      }
    }
  }

  Future<void> updateUnitPrice(double value) async {
    if (value != _unitPrice) {
      _unitPrice = value;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('unitPrice', value);
        _logger.i('Updated unitPrice to: $value');
        notifyListeners();
      } catch (e) {
        _logger.e('Failed to save unitPrice: $e');
      }
    }
  }

  // Calculate water savings based on actual vs max flow
  double calculateWaterSavings(double actualFlowRate, double duration) {
    if (actualFlowRate <= 0) return 0.0;

    // Calculate what would have been used at max flow
    double maxWaterUsed = _maxFlowRate * duration;
    // Calculate actual water used
    double actualWaterUsed = actualFlowRate * duration;
    // Calculate savings
    double savings = maxWaterUsed - actualWaterUsed;

    return savings > 0 ? savings : 0.0;
  }

  // Calculate cost savings in USD
  double calculateCostSavings(double waterSavings) {
    return waterSavings * _unitPrice;
  }

  // Calculate water saving percentage
  double calculateWaterSavingPercentage(
      double actualFlowRate, double duration) {
    if (actualFlowRate <= 0) return 0.0;

    double maxWaterUsed = _maxFlowRate * duration;
    double actualWaterUsed = actualFlowRate * duration;

    if (maxWaterUsed <= 0) return 0.0;

    double savings = maxWaterUsed - actualWaterUsed;
    return (savings / maxWaterUsed) * 100;
  }
}
