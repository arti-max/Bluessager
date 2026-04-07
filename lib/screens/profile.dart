import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Для работы с буфером обмена
import '../logic/app_state.dart';       // Подключаем логику

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: appState.name);
  }

  void _saveProfile() {
    setState(() {
      appState.name = _nameController.text;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Настройки сохранены')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль и Настройки')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
            const SizedBox(height: 16),
            
            // Копирование UID
            Card(
              color: Colors.deepPurple.withOpacity(0.2),
              child: ListTile(
                title: const Text('Ваш уникальный UID'),
                subtitle: Text(appState.uid, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent)),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: appState.uid)); // Копируем в буфер
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('UID скопирован в буфер обмена!')));
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Ваше имя',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            
            SwitchListTile(
              title: const Text('Режим Mesh-шлюза'),
              subtitle: const Text('Раздавать интернет устройствам по Bluetooth/Wi-Fi'),
              value: appState.isGatewayEnabled,
              onChanged: (val) {
                setState(() => appState.isGatewayEnabled = val);
              },
            ),
            SwitchListTile(
              title: const Text('Маскировка пакетов (ТСПУ)'),
              subtitle: const Text('Заворачивать трафик в HTTPS'),
              value: appState.isMaskingEnabled,
              onChanged: (val) {
                setState(() => appState.isMaskingEnabled = val);
              },
            ),
            const SizedBox(height: 40),
            
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              onPressed: _saveProfile,
              child: const Text('Сохранить'),
            )
          ],
        ),
      ),
    );
  }
}