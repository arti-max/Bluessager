import 'package:flutter/material.dart';
import '../logic/app_state.dart';
import 'chat.dart';
import 'profile.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Контроллер для отслеживания текущей вкладки
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Перерисовываем интерфейс при смене вкладки, чтобы обновить кнопку (FAB)
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- ДИАЛОГИ ---
  void _showAddFriendDialog() {
    final TextEditingController uidController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить друга'),
        content: TextField(
          controller: uidController,
          decoration: const InputDecoration(hintText: 'Введите UID друга'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (uidController.text.isNotEmpty) {
                setState(() => appState.friends.add({"uid": uidController.text, "name": ""}));
                Navigator.pop(context);
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog() {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Создать группу'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(hintText: 'Название группы'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                setState(() => appState.groups.add({"name": nameController.text, "members": 1}));
                Navigator.pop(context);
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  // Меню по долгому нажатию на группу
  void _showGroupOptionsMenu(int index) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Изменить название'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Тут будет переименование')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Настройки группы'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Покинуть группу', style: TextStyle(color: Colors.red)),
              onTap: () {
                setState(() => appState.groups.removeAt(index));
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Меню по долгому нажатию на друга
  void _showFriendOptionsMenu(int index) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Задать локальное имя'),
              onTap: () {
                Navigator.pop(context);
                // Тут в будущем будет диалог смены локального имени
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Удалить из друзей', style: TextStyle(color: Colors.red)),
              onTap: () {
                setState(() => appState.friends.removeAt(index));
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluessager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))
                .then((_) => setState(() {})),
          ),
        ],
        // Убрали isScrollable: true, теперь вкладки будут строго по центру
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.bluetooth), text: 'Рядом'),
            Tab(icon: Icon(Icons.person), text: 'Друзья'),
            Tab(icon: Icon(Icons.group), text: 'Группы'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Вкладка 1: Рядом (Радар)
          ListView.builder(
            itemCount: 2,
            itemBuilder: (context, index) => ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.bluetooth, color: Colors.white)),
              title: Text('Неизвестное устройство #${index + 1}'),
              // Если нашли устройство рядом, мы сразу видим его UID и статус
              subtitle: const Text('MESH-59281 • Сигнал: Отличный'), 
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerName: 'Устройство #${index + 1}'))),
            ),
          ),
          
          // Вкладка 2: Друзья
          ListView.builder(
            itemCount: appState.friends.length,
            itemBuilder: (context, index) {
              var friend = appState.friends[index];
              bool hasName = friend['name'].toString().isNotEmpty;

              return ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.person, color: Colors.white)),
                // Логика: Если есть имя — показываем имя, если нет — UID
                title: Text(hasName ? friend['name'] : friend['uid']),
                // Логика: Если есть имя, то UID показываем серым внизу
                subtitle: hasName ? Text(friend['uid'], style: const TextStyle(color: Colors.grey)) : const Text('Офлайн'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerName: hasName ? friend['name'] : friend['uid']))),
                onLongPress: () => _showFriendOptionsMenu(index), // Контекстное меню
              );
            },
          ),

          // Вкладка 3: Группы
          ListView.builder(
            itemCount: appState.groups.length,
            itemBuilder: (context, index) => ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.deepPurple, child: Icon(Icons.group, color: Colors.white)),
              title: Text(appState.groups[index]['name']),
              subtitle: Text('${appState.groups[index]['members']} участников'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerName: appState.groups[index]['name']))),
              onLongPress: () => _showGroupOptionsMenu(index), // Контекстное меню
            ),
          ),
        ],
      ),
      
      // Умная плавающая кнопка (зависит от открытой вкладки)
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Поиск новых устройств...')));
          } else if (_tabController.index == 1) {
            _showAddFriendDialog();
          } else if (_tabController.index == 2) {
            _showCreateGroupDialog();
          }
        },
        child: Icon(
          _tabController.index == 0 ? Icons.radar :
          _tabController.index == 1 ? Icons.person_add :
          Icons.group_add,
        ),
      ),
    );
  }
}