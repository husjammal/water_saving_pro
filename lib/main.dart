import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/connection_state_model.dart';
import 'models/data_state_model.dart';
import 'screens/home_screen.dart';

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
      ],
      child: MaterialApp(
        title: 'Water Monitor',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
