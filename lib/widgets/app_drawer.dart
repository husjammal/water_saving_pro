import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/connection_state_model.dart';
import '../models/data_state_model.dart';
import '../services/navigation_service.dart';
import '../screens/home_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/live_charts_screen.dart';
import '../screens/retrieve_data_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/help_screen.dart';
import '../screens/splash_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionStateModel>(
      builder: (context, connectionModel, child) {
        return Drawer(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E5979),
                  Color(0xFF2C5F7A),
                  Color(0xFF3A6580),
                ],
              ),
            ),
            child: Column(
              children: [
                // Header with app info
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                  child: Column(
                    children: [
                      // App Logo and Title
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Image.asset(
                                'assets/logo.png',
                                width: 32,
                                height: 32,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Water Monitor',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Smart Water Management',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Connection Status
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: connectionModel.isConnected
                              ? Colors.green.withOpacity(0.2)
                              : Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: connectionModel.isConnected
                                ? Colors.green
                                : Colors.red,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: connectionModel.isConnected
                                    ? Colors.green
                                    : Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Device Status',
                                    style: TextStyle(
                                      color: connectionModel.isConnected
                                          ? Colors.green
                                          : Colors.red,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    connectionModel.isConnected
                                        ? 'Connected'
                                        : 'Disconnected',
                                    style: TextStyle(
                                      color: connectionModel.isConnected
                                          ? Colors.green
                                          : Colors.red,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Navigation Items
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),

                        // Navigation Items
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            children: [
                              _buildDrawerItem(
                                context: context,
                                icon: Icons.dashboard,
                                title: 'Dashboard',
                                subtitle: 'Main control panel',
                                onTap: () {
                                  Navigator.pop(context); // Close drawer
                                  NavigationService().navigateToHome(context);
                                },
                                isSelected:
                                    NavigationService().isCurrentScreen('home'),
                              ),
                              const SizedBox(height: 8),
                              _buildDrawerItem(
                                context: context,
                                icon: Icons.show_chart,
                                title: 'Live Charts',
                                subtitle: 'Real-time data visualization',
                                onTap: () {
                                  Navigator.pop(context); // Close drawer
                                  NavigationService().navigateToLiveCharts(
                                      context, connectionModel);
                                },
                                isSelected: NavigationService()
                                    .isCurrentScreen('live_charts'),
                              ),
                              const SizedBox(height: 8),
                              _buildDrawerItem(
                                context: context,
                                icon: Icons.bar_chart,
                                title: 'Reports',
                                subtitle: 'Data analysis and reports',
                                onTap: () {
                                  Navigator.pop(context); // Close drawer
                                  NavigationService()
                                      .navigateToReports(context);
                                },
                                isSelected: NavigationService()
                                    .isCurrentScreen('reports'),
                              ),
                              const SizedBox(height: 8),
                              _buildDrawerItem(
                                context: context,
                                icon: Icons.cloud_download,
                                title: 'Retrieve Data',
                                subtitle: 'Download and manage data',
                                onTap: () {
                                  Navigator.pop(context); // Close drawer
                                  // For RetrieveDataScreen, we need to get the callbacks from the current context
                                  // This will be handled by the home screen navigation
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RetrieveDataScreen(
                                        onRetrieveData: () async {
                                          // This will be overridden by the actual implementation
                                        },
                                        onRetrieveAllData: () async {
                                          // This will be overridden by the actual implementation
                                        },
                                        onSetManualTimestamp: (context) async {
                                          // This will be overridden by the actual implementation
                                        },
                                        onClearCsvData: () async {
                                          // This will be overridden by the actual implementation
                                        },
                                        onCleanCsvData: (context) async {
                                          return {
                                            'success': false,
                                            'message': 'Not implemented'
                                          };
                                        },
                                      ),
                                    ),
                                  );
                                },
                                isSelected: NavigationService()
                                    .isCurrentScreen('retrieve_data'),
                              ),
                              const SizedBox(height: 8),
                              _buildDrawerItem(
                                context: context,
                                icon: Icons.settings,
                                title: 'Settings',
                                subtitle: 'App configuration',
                                onTap: () {
                                  Navigator.pop(context); // Close drawer
                                  // For SettingsScreen, we need to get the callbacks from the current context
                                  // This will be handled by the home screen navigation
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SettingsScreen(
                                        utcOffset: '+3',
                                        onDisconnectDevice: () {
                                          // This will be overridden by the actual implementation
                                        },
                                        onSyncTime: () async {
                                          // This will be overridden by the actual implementation
                                        },
                                        onReadDeviceTime: () async {
                                          // This will be overridden by the actual implementation
                                        },
                                        onUpdateUtcOffset: (value) {
                                          // This will be overridden by the actual implementation
                                        },
                                      ),
                                    ),
                                  );
                                },
                                isSelected: NavigationService()
                                    .isCurrentScreen('settings'),
                              ),
                              const SizedBox(height: 8),
                              _buildDrawerItem(
                                context: context,
                                icon: Icons.help_outline,
                                title: 'Help & Guide',
                                subtitle: 'App walkthrough and tips',
                                onTap: () {
                                  Navigator.pop(context); // Close drawer
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const HelpScreen(),
                                    ),
                                  );
                                },
                                isSelected: false,
                              ),
                              const SizedBox(height: 8),
                              _buildDrawerItem(
                                context: context,
                                icon: Icons.info_outline,
                                title: 'About',
                                subtitle: 'App information and credits',
                                onTap: () {
                                  Navigator.pop(context); // Close drawer
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const SplashScreen(),
                                    ),
                                  );
                                },
                                isSelected: false,
                              ),
                            ],
                          ),
                        ),

                        // Footer
                        Container(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              // Data Summary
                              Consumer<DataStateModel>(
                                builder: (context, dataModel, child) {
                                  return Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8F9FA),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE0E6ED),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1E5979)
                                                .withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.storage,
                                            color: Color(0xFF1E5979),
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Data Records',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Color(0xFF7F8C8D),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              Text(
                                                '${dataModel.csvData.length} records',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Color(0xFF2C3E50),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 16),

                              // App Version
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF1E5979).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Version 1.0.0',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF1E5979),
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawerItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isSelected,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF1E5979).withOpacity(0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(
                color: const Color(0xFF1E5979).withOpacity(0.3),
                width: 1,
              )
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF1E5979)
                        : const Color(0xFF1E5979).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected ? Colors.white : const Color(0xFF1E5979),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? const Color(0xFF1E5979)
                              : const Color(0xFF2C3E50),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? const Color(0xFF1E5979).withOpacity(0.7)
                              : const Color(0xFF7F8C8D),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E5979),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
