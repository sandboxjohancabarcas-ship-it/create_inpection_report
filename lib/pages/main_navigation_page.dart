import 'package:flutter/material.dart';
import 'package:wartungstool/pages/DoorListPage.dart';
import 'package:wartungstool/pages/job_selection_page.dart'; // Use JobSelectionPage as Manager view

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  _MainNavigationPageState createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const JobSelectionPage(), // Manager's view
    const DoorListPage(),     // Inspector's view
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.manage_accounts),
            label: 'Manager',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.door_front_door),
            label: 'Türen',
          ),
        ],
      ),
    );
  }
}
