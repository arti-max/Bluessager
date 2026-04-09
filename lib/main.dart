import 'package:flutter/material.dart';
import 'screens/chat_list.dart';
import 'logic/mesh_service.dart';
import 'logic/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appState.loadFromPrefs(); // Загружаем UID, имя, карму из хранилища
  runApp(const MeshMessengerApp());
}

class MeshMessengerApp extends StatefulWidget {
  const MeshMessengerApp({super.key});

  @override
  State<MeshMessengerApp> createState() => _MeshMessengerAppState();
}

class _MeshMessengerAppState extends State<MeshMessengerApp> {
  @override
  void initState() {
    super.initState();
    _startBackgroundBeacon();
  }

  void _startBackgroundBeacon() async {
    final ok = await meshService.requestPermissions();
    if (ok) meshService.startMeshNode(); // БЫЛО: startAdvertising()
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluessager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const ChatListScreen(),
    );
  }
}