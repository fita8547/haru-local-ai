import 'package:flutter/material.dart';

import 'screens/voice_screen.dart';
import 'theme.dart';

class HaruApp extends StatelessWidget {
  const HaruApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '하루',
      theme: buildHaruTheme(),
      home: const VoiceScreen(),
    );
  }
}
