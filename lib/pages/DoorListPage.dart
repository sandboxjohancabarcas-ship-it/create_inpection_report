import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/models.dart';
import 'new_door_page.dart';

class DoorListPage extends StatefulWidget {
  const DoorListPage({super.key});

  @override
  State<DoorListPage> createState() => _DoorListPageState();
}

class _DoorListPageState extends State<DoorListPage> {
  List<Door> doors = [];

  @override
  void initState() {
    super.initState();
    loadDoors();
  }

  Future<void> loadDoors() async {
    final list = await DatabaseService.getAllDoors();
    setState(() => doors = list);
  }

  Future<void> deleteDoor(int id) async {
    await DatabaseService.deleteDoor(id);
    await loadDoors();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Türenübersicht")),
      body: doors.isEmpty
          ? const Center(child: Text("Keine Türen vorhanden"))
          : ListView.builder(
              itemCount: doors.length,
              itemBuilder: (context, index) {
                final d = doors[index];

                return Dismissible(
                  key: Key(d.id.toString()),
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  direction: DismissDirection.startToEnd,
                  onDismissed: (_) => deleteDoor(d.id),
                  child: ListTile(
                    title: Text("Tür ${d.doorNumber}"),
                    subtitle: Text(d.roomDesignation),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            await deleteDoor(d.id);
                          },
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DoorInspectionForm(door: d),
                        ),
                      );
                      loadDoors();
                    },
                  ),

                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const DoorInspectionForm(),
            ),
          );
          loadDoors();
        },
      ),
    );
  }
}
