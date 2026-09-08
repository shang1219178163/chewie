import 'package:chewie_example/app/app.dart';
import 'package:chewie_example/app/theme.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChewieDemo',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const ChewieDemo(),
    );
  }
}
