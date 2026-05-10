import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'services/local_database_service.dart';
import 'services/database_service.dart';
import 'pages/main_navigation_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // -----------------------------------------
  // REQUIRED FOR WINDOWS / MACOS / LINUX
  // -----------------------------------------
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Initialize databases
  await LocalDatabaseService.getDb();
  await DatabaseService.getDb();

  // Start your real app
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: MainNavigationPage(),
    );
  }
}
