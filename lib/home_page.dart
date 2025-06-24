import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:greenhouse_monitor/greenhouse_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final userId = FirebaseAuth.instance.currentUser!.uid;
  final database = FirebaseDatabase.instance.ref();
  final uuid = const Uuid();

  Map<String, String> greenhouseNames = {};

  @override
  void initState() {
    super.initState();
    _loadGreenhouseNames();
  }

  Future<void> _loadGreenhouseNames() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith('greenhouse_name_'));

    final names = <String, String>{};
    for (var key in keys) {
      final name = prefs.getString(key);
      if (name != null) {
        final id = key.replaceFirst('greenhouse_name_', '');
        names[id] = name;
      }
    }

    if (!mounted) return;
    setState(() => greenhouseNames = names);
  }

  Future<void> _addGreenhouse() async {
    final newId = uuid.v4().substring(0, 8);
    final greenhouseRef = database.child('users/$userId/greenhouses/$newId');
    await greenhouseRef.set({'createdAt': DateTime.now().toIso8601String()});

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('greenhouse_name_$newId', 'Теплиця $newId');

    if (!mounted) return;
    setState(() {
      greenhouseNames[newId] = 'Теплиця $newId';
    });
  }

  Future<void> _confirmSignOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Вихід"),
        content: const Text("Ви дійсно хочете вийти?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Скасувати")),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text("Вийти")),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      // ignore: use_build_context_synchronously
      Navigator.of(context).pushReplacementNamed('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final greenhousesRef = database.child('users/$userId/greenhouses');

    return Scaffold(
      appBar: AppBar(
        title: const Text("Головне меню"),
        actions: [
          IconButton(
            onPressed: _confirmSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Вийти',
          ),
        ],
      ),
      body: StreamBuilder(
        stream: greenhousesRef.onValue,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text("Помилка при завантаженні даних"));
          }
          if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
            return const Center(child: Text("Немає теплиць"));
          }

          final data = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
          final items = data.keys.toList();

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final id = items[index];
              final name = greenhouseNames[id] ?? 'Теплиця $id';

              return ListTile(
                title: Text(name),
                subtitle: Text("ID: $id"),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GreenhouseDetailPage(
                        greenhouseId: id,
                        userId: userId,
                      ),
                    ),
                  ).then((_) => _loadGreenhouseNames());
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addGreenhouse,
        child: const Icon(Icons.add),
      ),
    );
  }
}
