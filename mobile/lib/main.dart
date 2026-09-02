import 'package:flutter/material.dart';

import 'src/ui/home_page.dart';

void main() => runApp(const LmcApp());

class LmcApp extends StatelessWidget {
  const LmcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Legal Metrology Checker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
