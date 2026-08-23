import 'package:flutter/material.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wartungstool/services/local_database_service.dart';
import 'package:wartungstool/services/database_service.dart';
import 'package:wartungstool/pages/DoorListPage.dart';
import 'package:wartungstool/pages/main_navigation_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    
    // Initialize Master Database (Manager Role)
    await DatabaseService.getDb();
  }

  // Initialize Local Working Database (Both Roles)
  await LocalDatabaseService.getDb();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WartungsTool',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: (Platform.isAndroid || Platform.isIOS)
          ? const DoorListPage()
          : const MainNavigationPage(),
    );
  }
}
