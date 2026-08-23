import 'package:flutter/material.dart';
import 'package:wartungstool/pages/DoorListPage.dart';
import 'package:wartungstool/pages/master_doors_page.dart';
import 'package:wartungstool/pages/manager_dashboard.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  _MainNavigationPageState createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const MasterDoorsPage(),   // Manager: Master-Portal (Aufträge, Türen, GAEB, Import/Export)
    const ManagerDashboard(),  // Manager: Fehlerkatalog, Konflikte & Import
    const DoorListPage(),      // Techniker / Inspector: Offline-Arbeitskopie
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey.shade600,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_customize),
            label: 'Master-Portal',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.rule_folder),
            label: 'Katalog & Freigaben',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.engineering),
            label: 'Techniker (App)',
          ),
        ],
      ),
    );
  }
}
