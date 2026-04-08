import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';

class AppState {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  // --- Профиль ---
  String uid = "MESH-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
  String name = "";
  bool isGatewayEnabled = false;
  bool isMaskingEnabled = false;

  // --- Система кармы и опыта ---
  int karma = 0;
  int xp = 0;
  int totalBytesSent = 0;
  int totalBytesRelayed = 0;

  String get rank {
    if (xp < 100)   return 'Новичок';
    if (xp < 500)   return 'Ретранслятор';
    if (xp < 2000)  return 'Узловой';
    if (xp < 10000) return 'Сетевик';
    return '⚡ Легенда Сети';
  }

  int get xpToNextLevel {
    if (xp < 100)   return 100;
    if (xp < 500)   return 500;
    if (xp < 2000)  return 2000;
    if (xp < 10000) return 10000;
    return 99999;
  }

  // --- Социальные данные ---
  List<Map<String, dynamic>> friends = [
    {"uid": "MESH-12345", "name": "Иван"},
    {"uid": "MESH-67890", "name": ""},
  ];
  List<Map<String, dynamic>> groups = [
    {"name": "Секретная группа", "members": 2, "id": "grp-001"},
  ];

  // --- История сообщений: ключ = UID собеседника ---
  final Map<String, List<ChatMessage>> messageHistory = {};

  // --- Активные подключения: endpointId -> uid ---
  final Map<String, String> connectedEndpoints = {};
  final Map<String, String> peerNames = {}; // uid -> displayName

  // --- Стримы для UI ---
  final _messageStreamCtrl = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get messageStream => _messageStreamCtrl.stream;

  final _connectionStreamCtrl = StreamController<void>.broadcast();
  Stream<void> get connectionStream => _connectionStreamCtrl.stream;

  // --- Методы ---
  void addMessage(String peerUid, ChatMessage message) {
    messageHistory[peerUid] ??= [];
    messageHistory[peerUid]!.add(message);
    _messageStreamCtrl.add(message);

    if (message.isMe) {
      xp += 1;
      totalBytesSent += message.text.length;
    } else {
      xp += 2;
    }
    saveStats();
  }

  void onPeerConnected(String endpointId, String peerUid, String peerDisplayName) {
    connectedEndpoints[endpointId] = peerUid;
    peerNames[peerUid] = peerDisplayName;
    karma += 5;
    xp += 10;
    _connectionStreamCtrl.add(null);
    saveStats();
  }

  void onPeerDisconnected(String endpointId) {
    connectedEndpoints.remove(endpointId);
    _connectionStreamCtrl.add(null);
  }

  bool isPeerConnected(String peerUid) =>
      connectedEndpoints.values.contains(peerUid);

  String? getEndpointForPeer(String peerUid) {
    for (final entry in connectedEndpoints.entries) {
      if (entry.value == peerUid) return entry.key;
    }
    return null;
  }

  List<ChatMessage> getHistory(String peerUid) =>
      messageHistory[peerUid] ?? [];

  // --- Persistence (SharedPreferences) ---
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    uid = prefs.getString('uid') ?? uid;
    name = prefs.getString('name') ?? '';
    karma = prefs.getInt('karma') ?? 0;
    xp = prefs.getInt('xp') ?? 0;
    totalBytesSent = prefs.getInt('totalBytesSent') ?? 0;
    isGatewayEnabled = prefs.getBool('isGatewayEnabled') ?? false;
    isMaskingEnabled = prefs.getBool('isMaskingEnabled') ?? false;
  }

  Future<void> saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uid', uid);
    await prefs.setString('name', name);
    await prefs.setBool('isGatewayEnabled', isGatewayEnabled);
    await prefs.setBool('isMaskingEnabled', isMaskingEnabled);
  }

  Future<void> saveStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('karma', karma);
    await prefs.setInt('xp', xp);
    await prefs.setInt('totalBytesSent', totalBytesSent);
  }
}

final appState = AppState();