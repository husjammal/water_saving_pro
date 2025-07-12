import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/live_charts_screen.dart';
import '../screens/retrieve_data_screen.dart';
import '../screens/settings_screen.dart';
import '../models/connection_state_model.dart';

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Current screen tracking
  String _currentScreen = 'home';
  String get currentScreen => _currentScreen;

  // Navigation methods - using push instead of pushReplacement to maintain stack
  void navigateToHome(BuildContext context) {
    if (_currentScreen == 'home') return;
    _currentScreen = 'home';
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => const HomeScreen(),
        settings: const RouteSettings(name: 'home'),
      ),
      (route) => false, // Remove all previous routes
    );
  }

  void navigateToLiveCharts(
      BuildContext context, ConnectionStateModel connectionModel) {
    if (_currentScreen == 'live_charts') return;
    _currentScreen = 'live_charts';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            LiveChartsScreen(liveDataStream: connectionModel.liveDataStream),
        settings: const RouteSettings(name: 'live_charts'),
      ),
    );
  }

  void navigateToReports(BuildContext context) {
    if (_currentScreen == 'reports') return;
    _currentScreen = 'reports';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ReportsScreen(),
        settings: const RouteSettings(name: 'reports'),
      ),
    );
  }

  void navigateToRetrieveData(
    BuildContext context, {
    required Future<void> Function() onRetrieveData,
    required Future<void> Function() onRetrieveAllData,
    required Future<void> Function(BuildContext) onSetManualTimestamp,
    required Future<void> Function() onClearCsvData,
    required Future<Map<String, dynamic>> Function(BuildContext) onCleanCsvData,
  }) {
    if (_currentScreen == 'retrieve_data') return;
    _currentScreen = 'retrieve_data';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RetrieveDataScreen(
          onRetrieveData: onRetrieveData,
          onRetrieveAllData: onRetrieveAllData,
          onSetManualTimestamp: onSetManualTimestamp,
          onClearCsvData: onClearCsvData,
          onCleanCsvData: onCleanCsvData,
        ),
        settings: const RouteSettings(name: 'retrieve_data'),
      ),
    );
  }

  void navigateToSettings(
    BuildContext context, {
    required String utcOffset,
    required VoidCallback onDisconnectDevice,
    required VoidCallback onSyncTime,
    required VoidCallback onReadDeviceTime,
    required Function(String) onUpdateUtcOffset,
  }) {
    if (_currentScreen == 'settings') return;
    _currentScreen = 'settings';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          utcOffset: utcOffset,
          onDisconnectDevice: onDisconnectDevice,
          onSyncTime: onSyncTime,
          onReadDeviceTime: onReadDeviceTime,
          onUpdateUtcOffset: onUpdateUtcOffset,
        ),
        settings: const RouteSettings(name: 'settings'),
      ),
    );
  }

  // Check if current screen matches
  bool isCurrentScreen(String screenName) {
    return _currentScreen == screenName;
  }

  // Update current screen (called when navigating via other means)
  void updateCurrentScreen(String screenName) {
    _currentScreen = screenName;
  }
}
