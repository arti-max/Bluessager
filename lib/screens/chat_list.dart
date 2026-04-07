import 'package:flutter/material.dart';
import '../logic/app_state.dart';
import '../logic/mesh_service.dart'; // Подключаем наш движок P2P
import 'chat.dart';
import 'profile.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Список реально найденных устройств рядом (вместо заглушек)
  List<Map<String, String>> _nearbyDevices = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });

    // Если включен режим шлюза в профиле, сразу начинаем раздачу себя (Advertising)
    if (appState.isGatewayEnabled) {
      meshService.startAdvertising();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- ЛОГИКА P2P (Радар) ---
  void _toggleSearch() async {
    if (_isSearching) {
      // TODO: Добавить остановку поиска в MeshService
      setState(() => _isSearching = false);
      return;
    }

    setState(() => _isSearching = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Запрос разрешений и запуск радара...')));

    // Запускаем реальный поиск устройств!
    await meshService.startDiscovery((endpointId, endpointName) {
      // Эта функция вызовется, когда телефон найдет кого-то рядом
      setState(() {
        // Проверяем, нет ли уже этого устройства в списке
        if (!_nearbyDevices.any((d) => d['id'] == endpointId)) {
          _nearbyDevices.add({
            'id': endpointId,
            'name': endpointName,
          });
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Найден: $endpointName')));
    });
  }

  // Подключение к найденному устройству
  void _connectToPeer(String endpointId, String peerName) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Подключение к $peerName...')));
    await meshService.connectToDevice(endpointId);
    
    // Переходим в чат (в будущем переход должен происходить только после успешного статуса CONNECTED)
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(peerName: peerName)),
    );
  }

  // --- ДИАЛОГИ (Без изменений) ---
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluessager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))
                .then((_) {
                  // Если после изменения профиля включили шлюз — начинаем раздачу
                  if (appState.isGatewayEnabled) meshService.startAdvertising();
                  setState(() {});
                }),
          ),
        ],
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
          // Вкладка 1: Реальный Радар
          _nearbyDevices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.radar, size: 80, color: _isSearching ? Colors.green : Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        _isSearching ? 'Ищем устройства вокруг...' : 'Нажмите кнопку поиска, чтобы найти устройства рядом',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _nearbyDevices.length,
                  itemBuilder: (context, index) {
                    var device = _nearbyDevices[index];
                    return ListTile(
                      leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.bluetooth, color: Colors.white)),
                      title: Text(device['name'] ?? 'Неизвестно'),
                      subtitle: Text('${device['id']} • Нажми для подключения'), 
                      onTap: () => _connectToPeer(device['id']!, device['name']!),
                    );
                  },
                ),
          
          // Вкладка 2: Друзья
          ListView.builder(
            itemCount: appState.friends.length,
            itemBuilder: (context, index) {
              var friend = appState.friends[index];
              bool hasName = friend['name'].toString().isNotEmpty;
              return ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.person, color: Colors.white)),
                title: Text(hasName ? friend['name'] : friend['uid']),
                subtitle: hasName ? Text(friend['uid'], style: const TextStyle(color: Colors.grey)) : const Text('Офлайн'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peerName: hasName ? friend['name'] : friend['uid']))),
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
            ),
          ),
        ],
      ),
      
      // Умная кнопка
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            _toggleSearch(); // Вызов реального поиска!
          } else if (_tabController.index == 1) {
            _showAddFriendDialog();
          } else if (_tabController.index == 2) {
            _showCreateGroupDialog();
          }
        },
        backgroundColor: _tabController.index == 0 && _isSearching ? Colors.green : null,
        child: Icon(
          _tabController.index == 0 
              ? (_isSearching ? Icons.stop : Icons.radar) 
              : _tabController.index == 1 ? Icons.person_add : Icons.group_add,
        ),
      ),
    );
  }
}