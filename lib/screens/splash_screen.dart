import 'dart:async';
import 'package:flutter/material.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  double _fontSize = 2;
  double _containerSize = 1.5;
  double _textOpacity = 0.0;
  double _containerOpacity = 0.0;

  late AnimationController _controller;
  late Animation<double> animation1;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3));
    animation1 = Tween<double>(begin: 40, end: 20).animate(
      CurvedAnimation(parent: _controller, curve: Curves.fastLinearToSlowEaseIn),
    )..addListener(() {
      setState(() {
        _textOpacity = 1.0;
      });
    });

    _controller.forward();

    Timer(const Duration(seconds: 2), () {
      setState(() {
        _fontSize = 1.06;
      });
    });

    Timer(const Duration(seconds: 3), () {
      setState(() {
        _containerSize = 2;
        _containerOpacity = 1;
      });
    });

    Timer(const Duration(seconds: 6), () {
      Navigator.pushReplacement(
        context,
        PageTransition(const HomeScreen()),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color.fromRGBO(255, 255, 255, 1),
      body: Stack(
        children: [
          Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 6000),
                curve: Curves.fastLinearToSlowEaseIn,
                height: height / _fontSize - 200,
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 5500),
                opacity: _textOpacity,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Water Monitor',
                    style: TextStyle(
                      color: const Color.fromRGBO(30, 89, 121, 1),
                      fontWeight: FontWeight.bold,
                      fontSize: animation1.value + 10,
                    ),
                  ),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 4500),
                opacity: _textOpacity,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 8, bottom: 3),
                      child: Center(
                        child: Text(
                          'Control & Monitor',
                          style: TextStyle(
                            color: Color.fromRGBO(30, 89, 121, 1),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 3000),
              curve: Curves.fastLinearToSlowEaseIn,
              opacity: _containerOpacity,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 3000),
                curve: Curves.fastLinearToSlowEaseIn,
                height: width / _containerSize,
                width: width / _containerSize,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: Image.asset('assets/logo.png'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PageTransition extends PageRouteBuilder {
  final Widget page;

  PageTransition(this.page)
      : super(
    pageBuilder: (context, animation, anotherAnimation) => page,
    transitionDuration: const Duration(milliseconds: 1500),
    transitionsBuilder: (context, animation, anotherAnimation, child) {
      animation = CurvedAnimation(
        curve: Curves.fastLinearToSlowEaseIn,
        parent: animation,
      );
      return Align(
        alignment: Alignment.center,
        child: SizeTransition(
          sizeFactor: animation,
          axisAlignment: 0,
          child: page,
        ),
      );
    },
  );
}