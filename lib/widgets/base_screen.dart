import 'package:flutter/material.dart';
import 'app_drawer.dart';

class BaseScreen extends StatelessWidget {
  final Widget child;
  final String title;
  final List<Widget>? actions;
  final bool showDrawer;
  final PreferredSizeWidget? appBar;

  const BaseScreen({
    super.key,
    required this.child,
    required this.title,
    this.actions,
    this.showDrawer = true,
    this.appBar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: appBar ??
          AppBar(
            title: Text(
              title,
              style: const TextStyle(
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
            actions: actions,
          ),
      drawer: showDrawer
          ? const AppDrawer(
              onDisableAutoStartLiveData: null,
              onEnableAutoStartLiveData: null,
              onNavigateToRetrieveData: null,
              onNavigateToSettings: null,
            )
          : null,
      body: child,
    );
  }
}
