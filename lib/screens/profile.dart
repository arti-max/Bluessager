import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль и Настройки')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
            const SizedBox(height: 16),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Ваше имя (визитка для P2P)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Режим Mesh-шлюза'),
              subtitle: const Text('Раздавать интернет устройствам по Bluetooth/Wi-Fi'),
              value: true,
              onChanged: (val) {},
            ),
            SwitchListTile(
              title: const Text('Маскировка пакетов (ТСПУ)'),
              subtitle: const Text('Заворачивать трафик в HTTPS (zapret API)'),
              value: false,
              onChanged: (val) {},
            ),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              onPressed: () => Navigator.pop(context),
              child: const Text('Сохранить'),
            )
          ],
        ),
      ),
    );
  }
}