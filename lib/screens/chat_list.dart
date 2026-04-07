import 'package:flutter/material.dart';
import 'chat.dart';
import 'profile.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Локальные чаты (P2P)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (_) => const ProfileScreen())
            ),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: 3, // Заглушка
        itemBuilder: (context, index) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green,
              child: Icon(Icons.bluetooth, color: Colors.white),
            ),
            title: Text('Устройство #${index + 1}'),
            subtitle: const Text('В сети (BLE) • Нажми чтобы начать чат'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChatScreen(peerName: 'Устройство #${index + 1}')),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Поиск новых устройств...'))
          );
        },
        icon: const Icon(Icons.radar),
        label: const Text('Искать'),
      ),
    );
  }
}