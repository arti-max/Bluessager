import 'package:flutter/material.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Переменные для хранения состояния
  bool _isGatewayEnabled = true;
  bool _isMaskingEnabled = false;
  final String _myUid = "MESH-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}"; // Генерируем фейковый UID

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль и Настройки')),
      body: SingleChildScrollView( // Добавили скролл, чтобы не было ошибок на маленьких экранах
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
            const SizedBox(height: 16),
            
            // Отображение UID
            Card(
              color: Colors.deepPurple.withOpacity(0.2),
              child: ListTile(
                title: const Text('Ваш уникальный UID'),
                subtitle: Text(_myUid, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent)),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('UID скопирован!')));
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            const TextField(
              decoration: InputDecoration(
                labelText: 'Ваше имя (визитка для P2P)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            
            // Рабочие переключатели
            SwitchListTile(
              title: const Text('Режим Mesh-шлюза'),
              subtitle: const Text('Раздавать интернет устройствам по Bluetooth/Wi-Fi'),
              value: _isGatewayEnabled,
              onChanged: (val) {
                setState(() => _isGatewayEnabled = val);
              },
            ),
            SwitchListTile(
              title: const Text('Маскировка пакетов (ТСПУ)'),
              subtitle: const Text('Заворачивать трафик в HTTPS (zapret API)'),
              value: _isMaskingEnabled,
              onChanged: (val) {
                setState(() => _isMaskingEnabled = val);
              },
            ),
            const SizedBox(height: 40),
            
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Настройки сохранены')));
                Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            )
          ],
        ),
      ),
    );
  }
}