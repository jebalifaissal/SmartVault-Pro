
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app/application_bootstrap.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase initialization temporarily disabled
  

  runApp(const ApplicationBootstrap());
}
