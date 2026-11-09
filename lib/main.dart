import 'package:flutter/material.dart';

import 'app/application_bootstrap.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
void main() async  {
   sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ApplicationBootstrap());
}
