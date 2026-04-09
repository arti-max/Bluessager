import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../logic/app_state.dart';
import '../logic/mesh_service.dart';
import 'chat.dart';
import 'profile.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, String>> _nearbyDevices = []; // {id, uid, name}
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));

    // Обновляем UI когда кто-то подключается/отключается
    appState.connectionStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- Радар ---
  void _toggleSearch() async {
    if (_isSearching) {
      meshService.stopDiscoveryOnly(); // теперь только убирает UI колбэк
      setState(() { _isSearching = false; _nearbyDevices.clear(); });
      return;
    }

    setState(() => _isSearching = true);

    final ok = await meshService.startDiscovery((endpointId, uid, displayName) {
      setState(() {
        if (!_nearbyDevices.any((d) => d['id'] == endpointId)) {
          _nearbyDevices.add({'id': endpointId, 'uid': uid, 'name': displayName});
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Найден: $displayName'), duration: const Duration(seconds: 2)),
      );
    });

    if (!ok) {
      setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Включите GPS и дайте все разрешения'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ));
      }
    }
  }

  void _connectToPeer(String endpointId, String peerUid, String peerName) async {
    await meshService.connectToDevice(endpointId);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ChatScreen(peerUid: peerUid, peerName: peerName),
    ));
  }

  // --- Long-press на друга ---
  void _showFriendOptions(BuildContext ctx, int index) {
    final friend = appState.friends[index];
    final hasName = (friend['name'] as String).isNotEmpty;

    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                hasName ? friend['name'] : friend['uid'],
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Переименовать'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameFriendDialog(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.grey),
              title: const Text('Скопировать UID'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: friend['uid']));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('UID скопирован')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Удалить', style: TextStyle(color: Colors.red)),
              onTap: () {
                setState(() => appState.friends.removeAt(index));
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRenameFriendDialog(int index) {
    final ctrl = TextEditingController(text: appState.friends[index]['name']);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Новое имя', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              setState(() => appState.friends[index]['name'] = ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  // --- Long-press на группу ---
  void _showGroupOptions(BuildContext ctx, int index) {
    showModalBottomSheet(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(appState.groups[index]['name'],
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Переименовать'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameGroupDialog(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Удалить группу', style: TextStyle(color: Colors.red)),
              onTap: () {
                setState(() => appState.groups.removeAt(index));
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRenameGroupDialog(int index) {
    final ctrl = TextEditingController(text: appState.groups[index]['name']);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать группу'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              setState(() => appState.groups[index]['name'] = ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  void _showAddFriendDialog() {
    final ctrl = TextEditingController();
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Добавить друга'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'UID друга',
                hintText: 'MESH-XXXXXXX',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Имя (необязательно)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                setState(() => appState.friends.add({
                  "uid": ctrl.text.trim(),
                  "name": nameCtrl.text.trim(),
                }));
                Navigator.pop(ctx);
              }
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Создать группу'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название группы',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.isNotEmpty) {
                setState(() => appState.groups.add({
                  "name": ctrl.text,
                  "members": 1,
                  "id": "grp-${DateTime.now().millisecondsSinceEpoch}",
                }));
                Navigator.pop(ctx);
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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ).then((_) => setState(() {})),
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
          // --- Вкладка: Рядом ---
          _nearbyDevices.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.radar, size: 80,
                          color: _isSearching ? Colors.green : Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        _isSearching
                            ? 'Сканируем эфир...'
                            : 'Нажмите кнопку чтобы найти устройства рядом',
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _nearbyDevices.length,
                  itemBuilder: (ctx, i) {
                    final d = _nearbyDevices[i];
                    final isConnected = appState.isPeerConnected(d['uid']!);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isConnected ? Colors.green : Colors.blueGrey,
                        child: const Icon(Icons.bluetooth, color: Colors.white),
                      ),
                      title: Text(d['name']!),
                      subtitle: Text(d['uid']!,
                          style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      trailing: isConnected
                          ? const Chip(label: Text('Онлайн'), backgroundColor: Colors.green)
                          : null,
                      onTap: () => _connectToPeer(d['id']!, d['uid']!, d['name']!),
                    );
                  },
                ),

          // --- Вкладка: Друзья ---
          appState.friends.isEmpty
              ? const Center(child: Text('Друзей пока нет.\nНажмите + чтобы добавить по UID.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: appState.friends.length,
                  itemBuilder: (ctx, i) {
                    final f = appState.friends[i];
                    final hasName = (f['name'] as String).isNotEmpty;
                    final isOnline = appState.isPeerConnected(f['uid']);
                    final lastMsgs = appState.getHistory(f['uid']);
                    final lastMsg = lastMsgs.isNotEmpty ? lastMsgs.last.text : null;

                    return InkWell(
                      onLongPress: () => _showFriendOptions(ctx, i),
                      child: ListTile(
                        leading: Stack(children: [
                          CircleAvatar(
                            backgroundColor: isOnline ? Colors.green[700] : Colors.blueAccent[700],
                            child: Text(
                              hasName
                                  ? (f['name'] as String)[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (isOnline)
                            Positioned(
                              right: 0, bottom: 0,
                              child: Container(
                                width: 12, height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black, width: 1.5),
                                ),
                              ),
                            ),
                        ]),
                        title: Text(hasName ? f['name'] : f['uid']),
                        subtitle: lastMsg != null
                            ? Text(lastMsg, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.grey))
                            : Text(f['uid'], style: const TextStyle(color: Colors.grey, fontSize: 11)),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ChatScreen(
                            peerUid: f['uid'],
                            peerName: hasName ? f['name'] : f['uid'],
                          )),
                        ),
                      ),
                    );
                  },
                ),

          // --- Вкладка: Группы ---
          appState.groups.isEmpty
              ? const Center(child: Text('Групп пока нет.\nНажмите + чтобы создать.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: appState.groups.length,
                  itemBuilder: (ctx, i) {
                    final g = appState.groups[i];
                    return InkWell(
                      onLongPress: () => _showGroupOptions(ctx, i),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.deepPurple,
                          child: Icon(Icons.group, color: Colors.white),
                        ),
                        title: Text(g['name']),
                        subtitle: Text('${g['members']} участников'),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ChatScreen(
                            peerUid: g['id'] ?? g['name'],
                            peerName: g['name'],
                            isGroup: true,
                          )),
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) _toggleSearch();
          else if (_tabController.index == 1) _showAddFriendDialog();
          else _showCreateGroupDialog();
        },
        backgroundColor: (_tabController.index == 0 && _isSearching) ? Colors.green : null,
        child: Icon(
          _tabController.index == 0
              ? (_isSearching ? Icons.stop : Icons.radar)
              : _tabController.index == 1
                  ? Icons.person_add
                  : Icons.group_add,
        ),
      ),
    );
  }
}