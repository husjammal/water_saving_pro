import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          'Help & Guide',
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1E5979),
                    const Color(0xFF2C5F7A),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.help_outline,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome to Water Monitor',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Smart Water Management System',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'This guide will walk you through the main features and functions of the Water Monitor app.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Main Features Section
            _buildSection(
              title: 'Main Features',
              icon: Icons.star,
              color: const Color(0xFFFF9800),
              children: [
                _buildFeatureItem(
                  icon: Icons.bluetooth,
                  title: 'Bluetooth Connectivity',
                  description:
                      'Connect to your water monitoring device via Bluetooth Low Energy (BLE) for real-time data transmission.',
                ),
                _buildFeatureItem(
                  icon: Icons.cloud_download,
                  title: 'Data Retrieval',
                  description:
                      'Download water usage data including flow rate (L/min), battery voltage, and tap duration from your device.',
                ),
                _buildFeatureItem(
                  icon: Icons.show_chart,
                  title: 'Live Visualization',
                  description:
                      'View real-time charts showing current water flow, battery status, and tap activity.',
                ),
                _buildFeatureItem(
                  icon: Icons.bar_chart,
                  title: 'Historical Reports',
                  description:
                      'Analyze historical data with customizable time periods and resolutions.',
                ),
                _buildFeatureItem(
                  icon: Icons.storage,
                  title: 'SD Card Management',
                  description:
                      'Monitor SD card status, file existence, and manage data storage on your device.',
                ),
                _buildFeatureItem(
                  icon: Icons.access_time,
                  title: 'Time Synchronization',
                  description:
                      'Sync device time with your phone and manage timezone settings.',
                ),
                _buildFeatureItem(
                  icon: Icons.volume_up,
                  title: 'Audio Feedback',
                  description:
                      'Hear water flow sounds and notification sounds for better user experience.',
                ),
                _buildFeatureItem(
                  icon: Icons.bug_report,
                  title: 'Debug System',
                  description:
                      'Comprehensive logging system with in-app viewer and export functionality.',
                ),
              ],
            ),

            // Dashboard Section
            _buildSection(
              title: 'Dashboard',
              icon: Icons.dashboard,
              color: const Color(0xFF1E5979),
              children: [
                _buildFeatureItem(
                  icon: Icons.cloud_download,
                  title: 'Retrieve Data',
                  description:
                      'Download water usage data from your device with incremental or full retrieval options.',
                ),
                _buildFeatureItem(
                  icon: Icons.bar_chart,
                  title: 'View Reports',
                  description:
                      'Analyze historical data with interactive charts and comprehensive summaries.',
                ),
                _buildFeatureItem(
                  icon: Icons.show_chart,
                  title: 'Live Charts',
                  description:
                      'Monitor real-time water flow, battery voltage, and tap duration with live charts.',
                ),
                _buildFeatureItem(
                  icon: Icons.settings,
                  title: 'Settings',
                  description:
                      'Configure device connection, sound settings, and debug options.',
                ),
                _buildFeatureItem(
                  icon: Icons.water_drop,
                  title: 'Flow Status Indicator',
                  description:
                      'Real-time visual indicator showing water flow status with start/stop times and duration tracking.',
                ),
                _buildFeatureItem(
                  icon: Icons.volume_up,
                  title: 'Sound Feedback',
                  description:
                      'All dashboard buttons play notification sounds when pressed for better user interaction feedback.',
                ),
                _buildFeatureItem(
                  icon: Icons.exit_to_app,
                  title: 'Enhanced Exit Dialog',
                  description:
                      'Modern, non-dismissible exit confirmation dialog with professional styling for better user experience.',
                ),
              ],
            ),

            // Live Charts Section
            _buildSection(
              title: 'Live Charts',
              icon: Icons.show_chart,
              color: const Color(0xFF2196F3),
              children: [
                _buildFeatureItem(
                  icon: Icons.water_drop,
                  title: 'Water Flow Rate (L/min)',
                  description:
                      'Real-time chart showing water consumption in liters per minute with live updates.',
                ),
                _buildFeatureItem(
                  icon: Icons.battery_full,
                  title: 'Battery Voltage',
                  description:
                      'Monitor device battery status with live voltage readings and trends.',
                ),
                _buildFeatureItem(
                  icon: Icons.touch_app,
                  title: 'Tap Duration',
                  description:
                      'Track how long taps are being used with real-time duration monitoring.',
                ),
                _buildFeatureItem(
                  icon: Icons.refresh,
                  title: 'Auto-Refresh',
                  description:
                      'Charts automatically update as new data comes in from your connected device.',
                ),
                _buildFeatureItem(
                  icon: Icons.expand,
                  title: 'Full-Screen Mode',
                  description:
                      'Expand charts to full screen for better visibility and detailed analysis.',
                ),
                _buildFeatureItem(
                  icon: Icons.water_drop,
                  title: 'Flow Detection',
                  description:
                      'Visual and audio feedback when water flow starts and stops with duration tracking.',
                ),
              ],
            ),

            // Reports Section
            _buildSection(
              title: 'Reports & Analysis',
              icon: Icons.bar_chart,
              color: const Color(0xFF4CAF50),
              children: [
                _buildFeatureItem(
                  icon: Icons.calendar_today,
                  title: 'Date Selection',
                  description:
                      'Choose any date to view historical data with easy navigation controls.',
                ),
                _buildFeatureItem(
                  icon: Icons.timeline,
                  title: 'Multiple Resolutions',
                  description:
                      'View data in different time resolutions: Hourly, Daily, Weekly, Monthly, or Yearly.',
                ),
                _buildFeatureItem(
                  icon: Icons.zoom_in,
                  title: 'Time Windows',
                  description:
                      'For hourly view, select specific 3-hour windows (e.g., 00:00-03:00, 09:00-12:00) for detailed analysis.',
                ),
                _buildFeatureItem(
                  icon: Icons.touch_app,
                  title: 'Interactive Charts',
                  description:
                      'Tap on chart points to see detailed information and exact values.',
                ),
                _buildFeatureItem(
                  icon: Icons.expand_more,
                  title: 'Expandable Summary',
                  description:
                      'View comprehensive data summary with water savings calculations and cost analysis.',
                ),
              ],
            ),

            // Data Retrieval Section
            _buildSection(
              title: 'Data Management',
              icon: Icons.cloud_download,
              color: const Color(0xFF9C27B0),
              children: [
                _buildFeatureItem(
                  icon: Icons.download,
                  title: 'Incremental Retrieval',
                  description:
                      'Download only new data since your last retrieval to save time and bandwidth.',
                ),
                _buildFeatureItem(
                  icon: Icons.download_done,
                  title: 'Full Data Download',
                  description:
                      'Download all available data from your device for complete analysis.',
                ),
                _buildFeatureItem(
                  icon: Icons.cleaning_services,
                  title: 'Data Cleaning',
                  description:
                      'Remove duplicate entries and filter out old data (older than 6 months) automatically.',
                ),
                _buildFeatureItem(
                  icon: Icons.delete_forever,
                  title: 'Data Clearing',
                  description:
                      'Clear all stored data to start fresh or free up storage space.',
                ),
                _buildFeatureItem(
                  icon: Icons.access_time,
                  title: 'Timestamp Management',
                  description:
                      'Set manual timestamps to control data retrieval periods and ensure accurate data synchronization.',
                ),
                _buildFeatureItem(
                  icon: Icons.file_download,
                  title: 'CSV Export',
                  description:
                      'Export data to CSV files in the Documents folder for external analysis.',
                ),
              ],
            ),

            // Settings Section
            _buildSection(
              title: 'Settings & Configuration',
              icon: Icons.settings,
              color: const Color(0xFF607D8B),
              children: [
                _buildFeatureItem(
                  icon: Icons.bluetooth,
                  title: 'Device Connection',
                  description:
                      'Manage Bluetooth connections, scan for devices, and monitor connection status.',
                ),
                _buildFeatureItem(
                  icon: Icons.sd_storage,
                  title: 'SD Card Status',
                  description:
                      'Check if SD card is present, verify file existence, and monitor storage capacity.',
                ),
                _buildFeatureItem(
                  icon: Icons.access_time,
                  title: 'Time Synchronization',
                  description:
                      'Sync device time with your phone and set UTC timezone offset for accurate timestamps.',
                ),
                _buildFeatureItem(
                  icon: Icons.refresh,
                  title: 'Device Time Reading',
                  description:
                      'Read current device time to verify synchronization and troubleshoot timing issues.',
                ),
                _buildFeatureItem(
                  icon: Icons.volume_up,
                  title: 'Sound Settings',
                  description:
                      'Enable/disable water flow sounds and notification sounds with test functionality.',
                ),
                _buildFeatureItem(
                  icon: Icons.water_drop,
                  title: 'Water Calculation Settings',
                  description:
                      'Configure maximum flow rate (L/s) and water unit price for savings calculations.',
                ),
                _buildFeatureItem(
                  icon: Icons.bug_report,
                  title: 'Debug Settings',
                  description:
                      'Enable debug logging, view logs in-app, export logs to file, and clear debug buffer.',
                ),
                _buildFeatureItem(
                  icon: Icons.search,
                  title: 'Advanced Debug Viewer',
                  description:
                      'Text search functionality and enhanced tag filtering in the debug logs viewer.',
                ),
                _buildFeatureItem(
                  icon: Icons.file_upload,
                  title: 'Log Export Enhancement',
                  description:
                      'Export debug logs to timestamped files in the Documents folder.',
                ),
              ],
            ),

            // Getting Started Section
            _buildSection(
              title: 'Getting Started',
              icon: Icons.play_circle,
              color: const Color(0xFFE91E63),
              children: [
                _buildFeatureItem(
                  icon: Icons.bluetooth_searching,
                  title: '1. Connect Your Device',
                  description:
                      'Tap "Connect Device" on the dashboard to scan for and connect to your water monitoring device.',
                ),
                _buildFeatureItem(
                  icon: Icons.sync,
                  title: '2. Sync Time',
                  description:
                      'After connection, the app will automatically sync the device time. You can also manually sync in Settings.',
                ),
                _buildFeatureItem(
                  icon: Icons.cloud_download,
                  title: '3. Retrieve Data',
                  description:
                      'Go to "Retrieve Data" to download your water usage data from the device.',
                ),
                _buildFeatureItem(
                  icon: Icons.show_chart,
                  title: '4. View Live Data',
                  description:
                      'Navigate to "Live Charts" to see real-time water monitoring data.',
                ),
                _buildFeatureItem(
                  icon: Icons.bar_chart,
                  title: '5. Analyze Reports',
                  description:
                      'Use "Reports" to view historical data and analyze water usage patterns.',
                ),
                _buildFeatureItem(
                  icon: Icons.settings,
                  title: '6. Configure Settings',
                  description:
                      'Adjust sound settings, water calculation parameters, and debug options in Settings.',
                ),
              ],
            ),

            // Tips Section
            _buildSection(
              title: 'Tips & Best Practices',
              icon: Icons.lightbulb,
              color: const Color(0xFFFFC107),
              children: [
                _buildFeatureItem(
                  icon: Icons.signal_wifi_4_bar,
                  title: 'Keep Device Nearby',
                  description:
                      'Ensure your water monitoring device is within Bluetooth range (typically 10 meters) for reliable connection.',
                ),
                _buildFeatureItem(
                  icon: Icons.battery_charging_full,
                  title: 'Monitor Battery',
                  description:
                      'Regularly check battery voltage in live charts to ensure your device has sufficient power.',
                ),
                _buildFeatureItem(
                  icon: Icons.schedule,
                  title: 'Regular Data Retrieval',
                  description:
                      'Download data regularly to prevent data loss and maintain accurate historical records.',
                ),
                _buildFeatureItem(
                  icon: Icons.cleaning_services,
                  title: 'Clean Data Periodically',
                  description:
                      'Use the data cleaning feature to remove duplicates and old data for better performance.',
                ),
                _buildFeatureItem(
                  icon: Icons.access_time,
                  title: 'Verify Time Sync',
                  description:
                      'Check device time synchronization regularly to ensure accurate timestamp recording.',
                ),
                _buildFeatureItem(
                  icon: Icons.volume_up,
                  title: 'Enable Sound Feedback',
                  description:
                      'Keep sound effects enabled for better user experience and water flow detection.',
                ),
                _buildFeatureItem(
                  icon: Icons.bug_report,
                  title: 'Use Debug Features',
                  description:
                      'Enable debug logging when troubleshooting issues and export logs for support.',
                ),
              ],
            ),

            // Troubleshooting Section
            _buildSection(
              title: 'Troubleshooting',
              icon: Icons.build,
              color: const Color(0xFF795548),
              children: [
                _buildFeatureItem(
                  icon: Icons.bluetooth_disabled,
                  title: 'Connection Issues',
                  description:
                      'Ensure Bluetooth is enabled, device is powered on, and within range. Restart app if needed.',
                ),
                _buildFeatureItem(
                  icon: Icons.sd_storage,
                  title: 'SD Card Problems',
                  description:
                      'Check SD card is properly inserted, has sufficient space, and is not corrupted.',
                ),
                _buildFeatureItem(
                  icon: Icons.access_time,
                  title: 'Time Sync Issues',
                  description:
                      'Verify device time synchronization and check UTC offset settings in the app.',
                ),
                _buildFeatureItem(
                  icon: Icons.volume_off,
                  title: 'Sound Issues',
                  description:
                      'Check device volume, ensure sounds are enabled in Settings, and verify sound files are available.',
                ),
                _buildFeatureItem(
                  icon: Icons.data_usage,
                  title: 'Data Retrieval Problems',
                  description:
                      'Ensure device is connected, has data to retrieve, and try incremental vs full retrieval.',
                ),
              ],
            ),

            // Developer Contact Section
            Container(
              margin: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1E5979),
                    const Color(0xFF2C5F7A),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Developer Support',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Hussam Eddin Al Jammal',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'For technical support, feature requests, or bug reports:',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildContactItem(
                      icon: Icons.business,
                      title: 'HusApps for Programming',
                      subtitle: 'Personal Business',
                      color: Colors.white,
                    ),
                    _buildContactItem(
                      icon: Icons.email,
                      title: 'Email',
                      subtitle: 'husjammal@gmail.com',
                      color: Colors.white,
                    ),
                    _buildContactItem(
                      icon: Icons.phone,
                      title: 'WhatsApp',
                      subtitle: '+963222314',
                      color: Colors.white,
                    ),
                    GestureDetector(
                      onTap: () async {
                        final Uri url = Uri.parse(
                            'https://www.linkedin.com/in/hussameddinaljammal/');
                        if (await canLaunchUrl(url)) {
                          await launchUrl(url,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      child: _buildContactItem(
                        icon: Icons.link,
                        title: 'LinkedIn',
                        subtitle: 'hussameddinaljammal',
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ),
                      child: const Text(
                        'When reporting issues, please include debug logs from Settings > Debug Settings > View Logs for faster resolution.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
          // Section Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
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
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          // Section Content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E5979).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF1E5979),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF7F8C8D),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: color.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
