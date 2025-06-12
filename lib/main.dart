import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(WaterMonitorApp());
}

class WaterMonitorApp extends StatelessWidget {
  const WaterMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Water Monitor',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomeScreen(),
    );
  }
}