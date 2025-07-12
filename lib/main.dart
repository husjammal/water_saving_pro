import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/connection_state_model.dart';
import 'models/data_state_model.dart';
import 'models/settings_model.dart';
import 'services/navigation_service.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionStateModel()),
        ChangeNotifierProvider(create: (_) => DataStateModel()),
        ChangeNotifierProvider(create: (_) => SettingsModel()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Water Monitor',
        navigatorKey: NavigationService().navigatorKey,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
