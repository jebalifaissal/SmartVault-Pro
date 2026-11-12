
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app/application_bootstrap.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  runApp(const ApplicationBootstrap());
}
