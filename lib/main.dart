import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const WaterMonitorApp());
}

class WaterMonitorApp extends StatelessWidget {
  const WaterMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Water Monitor',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const SplashScreen(),
    );
  }
}