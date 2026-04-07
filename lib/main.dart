import 'package:flutter/material.dart';
import 'screens/chat_list.dart';
import 'logic/mesh_service.dart';

void main() {
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
    // При запуске приложения сразу включаем раздачу себя (маяк)
    _startBackgroundBeacon();
  }

  void _startBackgroundBeacon() async {
    // Запрашиваем разрешения
    bool hasPermissions = await meshService.requestPermissions();
    if (hasPermissions) {
      // Если разрешения дали, начинаем постоянно кричать в эфир
      meshService.startAdvertising();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mesh Messenger',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple, 
          brightness: Brightness.dark
        ),
      ),
      home: const ChatListScreen(),
    );
  }
}