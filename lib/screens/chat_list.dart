import 'package:flutter/material.dart';
import '../logic/app_state.dart';
import 'chat.dart';
import 'profile.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  // Диалог добавления
  void _showAddActionSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.person_add),
              title: const Text('Добавить друга по UID'),
              onTap: () {
                Navigator.pop(context);
                _showAddFriendDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add),
              title: const Text('Создать группу'),
              onTap: () {
                Navigator.pop(context);
                setState(() => appState.groups.add({"name": "Новая группа", "members": 1}));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddFriendDialog() {
    final TextEditingController uidController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить друга'),
        content: TextField(
          controller: uidController,
          decoration: const InputDecoration(hintText: 'Введите UID'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (uidController.text.isNotEmpty) {
                setState(() => appState.friends.add(uidController.text));
                Navigator.pop(context);
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3, // Теперь 3 вкладки
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bluessager'),
          actions: [
            IconButton(
              icon: const Icon(Icons.account_circle),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))
                  .then((_) => setState(() {})), // Обновляем экран после закрытия профиля
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.bluetooth), text: 'Рядом'),
              Tab(icon: Icon(Icons.person), text: 'Друзья'),
              Tab(icon: Icon(Icons.group), text: 'Группы'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Вкладка 1: Рядом (Радар)
            ListView.builder(
              itemCount: 2,
              itemBuilder: (context, index) => ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.bluetooth, color: Colors.white)),
                title: Text('Неизвестное устройство #${index + 1}'),
                subtitle: const Text('В сети • BLE'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerName: 'Устройство #${index + 1}'))),
              ),
            ),
            
            // Вкладка 2: Друзья
            ListView.builder(
              itemCount: appState.friends.length,
              itemBuilder: (context, index) => ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.person, color: Colors.white)),
                title: Text(appState.friends[index]),
                subtitle: const Text('Офлайн'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerName: appState.friends[index]))),
              ),
            ),

            // Вкладка 3: Группы
            ListView.builder(
              itemCount: appState.groups.length,
              itemBuilder: (context, index) => ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.deepPurple, child: Icon(Icons.group, color: Colors.white)),
                title: Text(appState.groups[index]['name']),
                subtitle: Text('${appState.groups[index]['members']} участников'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerName: appState.groups[index]['name']))),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddActionSheet,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}