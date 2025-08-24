# Water Monitor App - Help & Guide

## Table of Contents
1. [Overview](#overview)
2. [Getting Started](#getting-started)
3. [Main Features](#main-features)
4. [Dashboard](#dashboard)
5. [Data Management](#data-management)
6. [Live Monitoring](#live-monitoring)
7. [Reports & Analytics](#reports--analytics)
8. [Settings](#settings)
9. [Debug System](#debug-system)
10. [Troubleshooting](#troubleshooting)
11. [Support & Contact](#support--contact)

---

## Overview

The Water Monitor app is a comprehensive smart water management system that allows you to monitor water usage in real-time, collect historical data, and analyze water consumption patterns. The app connects to water monitoring devices via Bluetooth and provides detailed insights into water flow, battery status, and usage patterns.

### Key Features
- **Real-time Water Flow Monitoring**: Live data streaming with flow detection
- **Bluetooth Connectivity**: Seamless connection to water monitoring devices
- **Data Collection & Storage**: Automatic CSV data management
- **Interactive Charts**: Visual representation of water usage patterns
- **Audio Feedback**: Sound notifications for water flow events
- **Debug System**: Comprehensive logging for troubleshooting
- **Export Functionality**: Data export to CSV files

---

## Getting Started

### 1. First Launch
1. Open the Water Monitor app
2. The app will display a beautiful splash screen with animations
3. Grant necessary permissions when prompted:
   - Bluetooth permissions
   - Location permissions (required for Bluetooth scanning)
   - Storage permissions (for data export)

### 2. Connecting Your Device
1. Tap the **"Connect Device"** button on the home screen
2. The app will scan for available Bluetooth devices
3. Select your water monitoring device from the list
4. The app will automatically connect and sync time with the device

### 3. Understanding the Interface
- **Home Screen**: Main dashboard with live data and quick access buttons
- **Navigation Drawer**: Access to all app features and settings
- **Status Indicators**: Real-time connection and flow status

---

## Main Features

### Dashboard
The main dashboard provides quick access to all app functions:

#### Live Data Display
- **Timestamp**: Current time from the device
- **Flow Rate**: Real-time water flow in liters per second
- **Battery Voltage**: Device battery status
- **Tap On/OFF**: Duration of tap activation

#### Flow Status Indicator
- **Active State**: Shows when water is flowing with blue indicators
- **Idle State**: Shows when no water flow is detected
- **Duration Tracking**: Displays flow start time and duration
- **Audio Feedback**: Plays water sounds when flow starts/stops

#### Quick Access Buttons
- **Retrieve Data**: Download data from device
- **View Reports**: Access historical data and analytics
- **Live Charts**: Real-time data visualization
- **Settings**: App configuration and device settings

### Data Management

#### Retrieving Data
1. Tap **"Retrieve Data"** from the dashboard
2. Choose data retrieval method:
   - **Incremental**: Download only new data since last retrieval
   - **Full Retrieval**: Download all available data
3. Monitor progress with real-time status updates
4. Data is automatically saved to CSV format

#### Data Export
- **Automatic Export**: Data is saved to `/storage/emulated/0/Documents/water_data.csv`
- **Manual Export**: Use the export function in settings
- **File Format**: Standard CSV with timestamp, flow rate, battery voltage, and tap duration

#### Data Cleaning
- **Remove Duplicates**: Automatic duplicate detection and removal
- **Filter Old Data**: Remove data older than 6 months
- **Data Validation**: Ensure data integrity and format

### Live Monitoring

#### Real-time Charts
1. Tap **"Live Charts"** from the dashboard
2. View three real-time charts:
   - **Water Flow Rate**: Live water consumption monitoring
   - **Tap Duration**: Tap activation patterns
   - **Battery Voltage**: Device power status
3. Charts update automatically every 500ms
4. Full-screen mode available for detailed viewing

#### Flow Detection
- **Start Detection**: Automatically detects when water flow begins
- **Stop Detection**: Detects when water flow stops
- **Duration Calculation**: Tracks flow duration in real-time
- **Visual Indicators**: Color-coded status with icons

### Reports & Analytics

#### Historical Data Analysis
1. Tap **"View Reports"** from the dashboard
2. Access comprehensive data summaries:
   - **Total Water Usage**: Cumulative water consumption
   - **Average Flow Rate**: Mean water flow patterns
   - **Peak Usage Times**: High consumption periods
   - **Battery Performance**: Device power efficiency

#### Interactive Charts
- **Time Series Analysis**: Water usage over time
- **Usage Patterns**: Daily, weekly, and monthly trends
- **Cost Analysis**: Water cost calculations based on unit price
- **Savings Tracking**: Water conservation metrics

#### Data Summary
- **Expandable Sections**: Click to view detailed information
- **Statistical Data**: Min, max, average, and total values
- **Time Periods**: Customizable date ranges for analysis
- **Export Options**: Save reports as CSV files

---

## Settings

### Device Connection
- **Connection Status**: Real-time Bluetooth connection status
- **Device Scanning**: Find and connect to water monitoring devices
- **Disconnect**: Safely disconnect from connected devices
- **Auto-reconnection**: Automatic reconnection on app resume

### Time Synchronization
- **UTC Offset**: Set your local timezone offset
- **Device Time**: View current device time
- **Time Sync**: Synchronize device time with app
- **Manual Time Reading**: Read current device time

### Sound Settings
- **Water Flow Sounds**: Enable/disable audio feedback
- **Sound Testing**: Test water flow start/stop sounds
- **Notification Sounds**: Audio feedback for dashboard buttons
- **Volume Control**: Adjust sound levels

### Water Calculation Settings
- **Maximum Flow Rate**: Set upper limit for flow rate calculations
- **Unit Price**: Configure water cost per liter
- **Savings Calculations**: Automatic cost and savings analysis
- **Custom Thresholds**: Set custom flow rate limits

### Debug Settings
- **Console Logging**: Enable detailed debug logging
- **Log Viewer**: View debug logs within the app
- **Log Export**: Export debug logs to files
- **Buffer Management**: Clear and manage log buffers

### SD Card Status
- **Card Detection**: Check if SD card is present
- **File Status**: Verify data file existence
- **Storage Information**: View file size and modification date
- **Status Monitoring**: Real-time SD card health

---

## Debug System

### Enabling Debug Mode
1. Go to **Settings** → **Debug Settings**
2. Toggle **"Console Debug Logging"** to enable
3. Debug logs will be sent to console and in-app viewer

### Debug Log Viewer
1. In **Debug Settings**, tap **"View Logs"**
2. View logs with:
   - **Tag Filtering**: Filter by BT, LIVE, CHARTS, etc.
   - **Text Search**: Search for specific words or phrases
   - **Color-coded Levels**: Different colors for ERROR, WARN, INFO, DEBUG
   - **Real-time Updates**: Refresh logs without leaving screen

### Log Management
- **Clear Buffer**: Remove all stored debug logs
- **Export Logs**: Save debug logs to file in Documents folder
- **Log Levels**: Different severity levels for filtering
- **Tag System**: Organized logging by feature area

### Debug Information
Debug logs include:
- **Bluetooth Communication**: Connection status and data transfer
- **Live Data**: Real-time sensor data processing
- **Chart Updates**: Data visualization events
- **Error Tracking**: Detailed error information and stack traces

---

## Troubleshooting

### Connection Issues
**Problem**: Cannot connect to device
**Solutions**:
1. Ensure device is turned on and nearby
2. Check Bluetooth is enabled on your phone
3. Restart the app and try scanning again
4. Verify device is not connected to another app

**Problem**: Connection drops frequently
**Solutions**:
1. Move closer to the device
2. Check for interference from other Bluetooth devices
3. Restart both the app and the monitoring device
4. Check device battery level

### Data Issues
**Problem**: No data being received
**Solutions**:
1. Verify device is properly connected
2. Check if live data is enabled
3. Restart the data collection process
4. Check device sensors are working

**Problem**: Data appears incorrect
**Solutions**:
1. Sync device time with app
2. Check device calibration
3. Verify sensor connections
4. Contact support for device-specific issues

### Performance Issues
**Problem**: App is slow or unresponsive
**Solutions**:
1. Clear debug buffer if debug mode is enabled
2. Restart the app
3. Check available storage space
4. Close other background apps

**Problem**: Charts not updating
**Solutions**:
1. Ensure live data is enabled
2. Check connection status
3. Restart the live charts screen
4. Verify device is sending data

### Export Issues
**Problem**: Cannot export data
**Solutions**:
1. Check storage permissions
2. Verify Documents folder is accessible
3. Ensure sufficient storage space
4. Try exporting smaller data sets

---

## Support & Contact

### Developer Information
**Hussam Eddin Al Jammal**
- **Company**: HusApps for Programming (Personal Job)
- **Email**: husjammal@gmail.com
- **WhatsApp**: +963222314
- **LinkedIn**: [hussameddinaljammal](https://www.linkedin.com/in/hussameddinaljammal/)

### Getting Help
1. **Check this guide** for common solutions
2. **Enable debug logging** to gather diagnostic information
3. **Contact via email** with detailed problem description
4. **Include debug logs** when reporting issues
5. **Provide device information** and app version

### Bug Reports
When reporting issues, please include:
- **App version**: Current app version number
- **Device model**: Your phone/tablet model
- **Android version**: Operating system version
- **Problem description**: Detailed explanation of the issue
- **Steps to reproduce**: How to recreate the problem
- **Debug logs**: If debug mode is enabled
- **Screenshots**: Visual evidence of the issue

### Feature Requests
We welcome suggestions for new features and improvements:
- **Email your ideas** to husjammal@gmail.com
- **Include detailed descriptions** of requested features
- **Explain the benefits** and use cases
- **Provide examples** if possible

---

## Version History

### Recent Updates
- **Enhanced Exit Dialog**: Improved app exit confirmation with modern UI
- **Dashboard Sound Effects**: Audio feedback for all dashboard button presses
- **Advanced Debug Viewer**: In-app debug log viewing with search and filtering
- **Flow Detection System**: Real-time water flow start/stop detection
- **Sound System**: Water flow audio feedback with customizable settings
- **LinkedIn Integration**: Direct link to developer's LinkedIn profile
- **Comprehensive Help System**: Detailed documentation and troubleshooting guide

### Technical Improvements
- **Performance Optimization**: Improved app responsiveness and data handling
- **Memory Management**: Better resource utilization and cleanup
- **Error Handling**: Enhanced error detection and recovery
- **UI/UX Enhancements**: Modern design with smooth animations
- **Data Validation**: Improved data integrity and format checking

---

## Legal Information

### Privacy Policy
- The app does not collect personal information
- All data is stored locally on your device
- No data is transmitted to external servers
- Bluetooth data is used only for device communication

### Terms of Use
- Use the app responsibly and in accordance with local regulations
- Ensure proper device installation and maintenance
- Contact support for technical issues
- Respect intellectual property rights

### Warranty
- The app is provided "as is" without warranty
- Developer is not liable for data loss or device damage
- Regular backups are recommended
- Contact support for technical assistance

---

*Last Updated: December 2024*
*Version: 1.0.0*
*Developer: Hussam Eddin Al Jammal - HusApps for Programming* 