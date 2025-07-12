# Water Monitor App - Debug Guide

## Lightweight Debug Service

The app now includes a lightweight debug service that provides console logging capabilities with an in-app viewer and file export functionality. This allows for easy debugging while maintaining app stability.

## How to Use

### 1. Enable Debug Logging

1. Open the app
2. Go to **Settings** screen
3. Scroll down to the **Debug Settings** section
4. Toggle the **Console Debug Logging** switch to enable

### 2. View Debug Logs

Debug logs can be viewed in multiple ways:

#### In-App Viewer
1. In the **Debug Settings** section, tap **"View Logs"**
2. This opens a dedicated debug logs viewer screen within the app
3. Logs are displayed with color-coded levels and tag filtering
4. Use the refresh button to update logs in real-time

#### Search and Filter
- **Text Search**: Use the search field to find specific words in logs
- **Tag Filtering**: Filter logs by BT, LIVE, CHARTS, etc.
- **Real-time Updates**: Search and filters update as you type

### 3. Export Debug Logs

1. In the **Debug Settings** section, tap **"Export Logs"**
2. Debug logs are saved as a file in the Documents folder
3. File is saved as `debug_logs_YYYY-MM-DD_HH-mm-ss.txt`
4. Success/failure feedback is shown via snackbar

### 4. Clear Debug Buffer

1. In the **Debug Settings** section, tap **"Clear Buffer"**
2. All stored debug logs are cleared
3. Confirmation is shown via snackbar

## Debug Features

### Automatic Logging
- **Bluetooth Communication**: All BT commands and responses
- **Live Data**: Water flow, battery, and tap duration data
- **Chart Data**: Real-time chart updates and data processing
- **Error Handling**: All errors and exceptions with stack traces

### Tag System
- **BT**: Bluetooth communication logs
- **LIVE**: Live data stream logs
- **CHARTS**: Chart data processing logs
- **ERROR**: Error and exception logs

### File Export
- **Location**: Documents folder (`/storage/emulated/0/Documents/`)
- **Format**: Plain text with timestamps and tags
- **Naming**: `debug_logs_YYYY-MM-DD_HH-mm-ss.txt`
- **Content**: All debug logs with proper formatting

## Recent Updates

### Enhanced Exit Dialog
- **Modern UI**: Rounded corners, shadows, and better styling
- **Clear Messaging**: Descriptive text about closing the app
- **Non-dismissible**: Prevents accidental app closure
- **Styled Buttons**: Cancel (gray) and Exit (red) buttons

### Dashboard Sound Effects
- **Notification Sounds**: All 4 dashboard buttons play sounds when pressed
- **Sound Service**: Integrated with existing water flow sound system
- **User Control**: Sounds can be enabled/disabled in Settings
- **Feedback**: Provides audio confirmation of button presses

### Advanced Debug Viewer
- **In-App Display**: View logs directly within the app
- **Search Functionality**: Find specific words in log entries
- **Tag Filtering**: Filter logs by BT, LIVE, CHARTS, etc.
- **Real-time Updates**: Refresh logs without leaving the screen
- **Color-coded Levels**: Different colors for ERROR, WARN, INFO, DEBUG

### Flow Detection System
- **Real-time Detection**: Automatically detects water flow start/stop
- **Visual Indicators**: Dynamic icons and color changes
- **Flow Status Card**: Shows detailed flow timing and duration
- **Audio Feedback**: Plays sounds when water starts/stops flowing

### Sound System Enhancements
- **Water Flow Sounds**: Audio feedback for flow detection
- **Dashboard Sounds**: Notification sounds for button presses
- **Settings Control**: Enable/disable sounds in Settings screen
- **Test Function**: Test sounds directly from Settings

### File Export System
- **CSV Export**: Export water data to Documents folder
- **Debug Log Export**: Export debug logs as text files
- **Automatic Naming**: Timestamped file names
- **User Feedback**: Success/failure notifications

### Developer Contact Integration
- **LinkedIn Link**: Clickable LinkedIn profile link that opens in mobile browser
- **Contact Information**: Complete developer contact details in Help & Guide
- **Professional Branding**: HusApps for programming branding
- **Support Information**: Clear support contact details

## Troubleshooting

### Common Issues
1. **Debug logs not showing**: Ensure debug logging is enabled in Settings
2. **Export fails**: Check storage permissions and Documents folder access
3. **Search not working**: Verify text is entered in search field
4. **Tag filtering empty**: Check if logs contain the specified tags

### Performance Notes
- Debug logging has minimal performance impact
- Log buffer is limited to prevent memory issues
- Export function processes logs efficiently
- Search and filtering are optimized for real-time use

## Support

For technical support or bug reports, contact the developer:

- **Developer**: HusApps for programming
- **Email**: husjammal@gmail.com
- **WhatsApp**: +963222314
- **LinkedIn**: [hussameddinaljammal](https://www.linkedin.com/in/hussameddinaljammal/) (clickable link opens in mobile browser)

When reporting issues, please include debug logs from Settings > Debug Settings > View Logs for faster resolution. 