import 'package:flutter/material.dart';


class SmartVaultMaterialApp extends StatelessWidget {
  const SmartVaultMaterialApp({required this.home, super.key});

  final Widget home;

  static const _teal = Color(0xFF087E78);
  static const _ink = Color(0xFF172B3A);
  static const _canvas = Color(0xFFF7F9FA);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartVault Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _teal,
          primary: _teal,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: _ink,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: _ink,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            height: 1.15,
            letterSpacing: -0.8,
          ),
          bodyLarge: TextStyle(color: _ink, fontSize: 16),
          bodyMedium: TextStyle(color: Color(0xFF657582), fontSize: 14),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          hintStyle: const TextStyle(color: Color(0xFF9AA7B0), fontSize: 14),
          prefixIconColor: const Color(0xFF82919C),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _teal, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD94F4F)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD94F4F), width: 1.5),
          ),
        ),
      ),
      home: home,
    );
  }
}
