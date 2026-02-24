import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/hrv_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0a0a0a),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const HrvApp());
}

class HrvApp extends StatelessWidget {
  const HrvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HRV Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0a0a0a),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFff6b6b),
          secondary: Color(0xFF4ecdc4),
          surface: Color(0xFF1a1a2e),
          onSurface: Colors.white,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const HrvScreen(),
    );
  }
}
