import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'screens/home_screen.dart';

class BlinkyApp extends StatelessWidget {
  const BlinkyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlinkyApp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const HomeScreen(),
    );
  }
}
