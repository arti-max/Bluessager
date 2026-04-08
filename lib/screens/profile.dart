import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../logic/app_state.dart';

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
    appState.name = _nameController.text;
    appState.saveProfile();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Профиль сохранён')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final xpProgress = appState.xp / appState.xpToNextLevel;

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // --- Аватар и ранг ---
            const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
            const SizedBox(height: 8),
            Text(appState.rank, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),

            // XP прогресс-бар
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: xpProgress.clamp(0.0, 1.0),
                    backgroundColor: Colors.grey[800],
                    color: Colors.deepPurpleAccent,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${appState.xp} / ${appState.xpToNextLevel} XP',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // --- Карточки статистики ---
            Row(
              children: [
                _StatCard(label: 'Карма', value: '${appState.karma}', icon: Icons.favorite, color: Colors.pinkAccent),
                const SizedBox(width: 8),
                _StatCard(label: 'XP', value: '${appState.xp}', icon: Icons.bolt, color: Colors.amber),
                const SizedBox(width: 8),
                _StatCard(
                  label: 'Отправлено',
                  value: _formatBytes(appState.totalBytesSent),
                  icon: Icons.upload,
                  color: Colors.greenAccent,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // --- UID ---
            Card(
              color: Colors.deepPurple.withOpacity(0.2),
              child: ListTile(
                title: const Text('Ваш UID', style: TextStyle(fontSize: 12, color: Colors.grey)),
                subtitle: Text(
                  appState.uid,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurpleAccent),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: appState.uid));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('UID скопирован')),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // --- Имя ---
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Отображаемое имя',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 16),

            // --- Переключатели ---
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Режим Gateway'),
                    subtitle: const Text('Раздавать интернет через Mesh'),
                    value: appState.isGatewayEnabled,
                    onChanged: (v) => setState(() => appState.isGatewayEnabled = v),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Маскировка (ТСПУ)'),
                    subtitle: const Text('Трафик в HTTPS-обёртке'),
                    value: appState.isMaskingEnabled,
                    onChanged: (v) => setState(() => appState.isMaskingEnabled = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
              onPressed: _saveProfile,
              icon: const Icon(Icons.save),
              label: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ),
      ),
    );
  }
}