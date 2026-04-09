import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_state.dart';
import '../models/chat_message.dart';

class MeshService {
  static final MeshService _instance = MeshService._internal();
  factory MeshService() => _instance;
  MeshService._internal();

  final Strategy strategy = Strategy.P2P_CLUSTER;
  final String serviceId = "com.bluessager.mesh";

  bool _isAdvertising = false;
  bool _isDiscovering = false;

  Timer? _pingTimer;
  Timer? _meshHealthTimer; // единый таймер вместо двух

  void Function(String, String, String)? _onDeviceFoundCallback;

  final Map<String, String> _pendingNames = {};

  // UID пиров которым МЫ делали requestConnection (чтобы не дублировать)
  final Set<String> _outgoingRequests = {};

  // --- РАЗРЕШЕНИЯ ---
  Future<bool> requestPermissions() async {
    final loc = await Permission.locationWhenInUse.request();
    if (!loc.isGranted) {
      print("❌ Локация не выдана");
      return false;
    }

    final btScan      = await Permission.bluetoothScan.request();
    final btConnect   = await Permission.bluetoothConnect.request();
    final btAdvertise = await Permission.bluetoothAdvertise.request();
    final btClassic   = await Permission.bluetooth.request();
    await Permission.nearbyWifiDevices.request();

    final hasNew = btScan.isGranted && btConnect.isGranted && btAdvertise.isGranted;
    final hasOld = btClassic.isGranted;

    if (!hasNew && !hasOld) {
      print("❌ Bluetooth права не выданы. New=$hasNew Old=$hasOld");
      return false;
    }
    print("✅ Права: New=$hasNew Old=$hasOld");
    return true;
  }

  // --- ПАРСИНГ ПАКЕТОВ ---
  void _handlePayload(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;

    try {
      final raw = utf8.decode(payload.bytes!);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final type = data['type'] as String?;

      if (type == 'msg') {
        final peerUid = appState.connectedEndpoints[endpointId] ?? endpointId;
        appState.addMessage(
          peerUid,
          ChatMessage(
            id: data['id'] ?? '${DateTime.now().millisecondsSinceEpoch}',
            senderUid: peerUid,
            peerUid: peerUid,
            text: data['text'] as String,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              data['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch,
            ),
            isMe: false,
          ),
        );

      } else if (type == 'ping') {
        _sendPacket(endpointId, {
          'type': 'pong',
          'uid': appState.uid,
          'name': appState.name.isNotEmpty ? appState.name : appState.uid,
        });
        final senderUid = data['uid'] as String?;
        if (senderUid != null) {
          appState.connectedEndpoints[endpointId] = senderUid;
          appState.peerNames[senderUid] = data['name'] as String? ?? senderUid;
          appState.peerLastSeen[senderUid] = DateTime.now();
          appState.notifyConnectionChange();
        }

      } else if (type == 'pong') {
        final senderUid = data['uid'] as String?;
        if (senderUid != null) {
          appState.connectedEndpoints[endpointId] = senderUid;
          appState.peerNames[senderUid] = data['name'] as String? ?? senderUid;
          appState.peerLastSeen[senderUid] = DateTime.now();
          appState.notifyConnectionChange();
        }
      }

    } catch (e) {
      print("Ошибка парсинга: $e");
    }
  }

  // --- ОТПРАВКА ПАКЕТА ---
  bool _sendPacket(String endpointId, Map<String, dynamic> data) {
    try {
      Nearby().sendBytesPayload(
        endpointId,
        Uint8List.fromList(utf8.encode(jsonEncode(data))),
      );
      return true;
    } catch (e) {
      print("Ошибка пакета к $endpointId: $e");
      return false;
    }
  }

  // --- ОБРАБОТЧИКИ СОЕДИНЕНИЯ ---

  void _onConnectionInitiated(String? endpointId, ConnectionInfo info) {
    if (endpointId == null) return;
    print("🤝 Инициация от ${info.endpointName} ($endpointId)");
    _pendingNames[endpointId] = info.endpointName;

    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: _handlePayload,
      onPayloadTransferUpdate: (id, update) {},
    );
  }

  void _onConnectionResult(String? endpointId, Status status) {
    if (endpointId == null) return;
    print("📶 Результат $endpointId: $status");
    _outgoingRequests.remove(endpointId);

    if (status == Status.CONNECTED) {
      final displayName = _pendingNames.remove(endpointId) ?? endpointId;
      appState.onPeerConnected(endpointId, endpointId, displayName);

      Future.delayed(const Duration(milliseconds: 300), () {
        _sendPacket(endpointId, {
          'type': 'ping',
          'uid': appState.uid,
          'name': appState.name.isNotEmpty ? appState.name : appState.uid,
        });
      });

    } else if (status == Status.ALREADY_CONNECTED_TO_ENDPOINT) {
      // Не ошибка — просто уже подключены (гонка двух requestConnection)
      _pendingNames.remove(endpointId);
      print("ℹ️ Уже подключены к $endpointId");

    } else {
      _pendingNames.remove(endpointId);
      print("❌ Не подключились: $status");
    }
  }

  void _onDisconnected(String? endpointId) {
    if (endpointId == null) return;
    print("🔌 Отключён: $endpointId");
    _pendingNames.remove(endpointId);
    _outgoingRequests.remove(endpointId);
    appState.onPeerDisconnected(endpointId);
  }

  // --- АВТО-КОННЕКТ (с защитой от гонки) ---
  Future<void> _autoConnect(String endpointId, String remoteEndpointName) async {
    // Уже подключены
    if (appState.connectedEndpoints.containsKey(endpointId)) return;
    // Уже в процессе рукопожатия
    if (_pendingNames.containsKey(endpointId)) return;
    // Уже отправили запрос
    if (_outgoingRequests.contains(endpointId)) return;

    // ЗАЩИТА ОТ ГОНКИ: коннектится только тот, чьё имя лексически МЕНЬШЕ
    // Второй получит onConnectionInitiated от первого и просто примет
    final myName = appState.name.isNotEmpty ? appState.name : appState.uid;
    if (myName.compareTo(remoteEndpointName) >= 0) {
      print("⏳ Ждём входящего коннекта от $remoteEndpointName (их имя меньше)");
      return;
    }

    print("📞 Коннектимся к $remoteEndpointName ($endpointId)");
    _outgoingRequests.add(endpointId);

    try {
      await Nearby().requestConnection(
        myName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      print("Авто-коннект $endpointId: $e");
      _outgoingRequests.remove(endpointId);
    }
  }

  // --- СТАРТ УЗЛА ---
  Future<void> startMeshNode() async {
    if (!await requestPermissions()) {
      print("❌ Mesh не запущен — нет прав");
      return;
    }

    await _doStartAdvertising();
    await Future.delayed(const Duration(milliseconds: 800));
    await _doStartDiscovery();

    _startTimers();
    print("✅ Mesh-узел запущен");
  }

  // --- РАЗДАЧА ---
  Future<bool> _doStartAdvertising() async {
    if (_isAdvertising) return true;
    try {
      _isAdvertising = await Nearby().startAdvertising(
        appState.name.isNotEmpty ? appState.name : appState.uid,
        strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: serviceId,
      );
      print("📢 Advertising: $_isAdvertising");
      return _isAdvertising;
    } catch (e) {
      print("Ошибка advertising: $e");
      _isAdvertising = false;
      return false;
    }
  }

  Future<bool> startAdvertising() => _doStartAdvertising();

  // --- ПОИСК ВНУТРЕННИЙ ---
  Future<bool> _doStartDiscovery() async {
    // Сначала останавливаем если был запущен — для чистого перезапуска
    if (_isDiscovering) {
      try {
        Nearby().stopDiscovery();
      } catch (_) {}
      _isDiscovering = false;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    try {
      _isDiscovering = await Nearby().startDiscovery(
        appState.name.isNotEmpty ? appState.name : appState.uid,
        strategy,
        onEndpointFound: (endpointId, endpointName, svcId) {
          if (endpointId == null || endpointName == null) return;
          print("👁 Найден: $endpointName ($endpointId)");

          _onDeviceFoundCallback?.call(endpointId, endpointId, endpointName);
          _autoConnect(endpointId, endpointName);
        },
        onEndpointLost: (endpointId) {
          if (endpointId != null) {
            print("💨 Потерян: $endpointId");
            // НЕ удаляем из connectedEndpoints — соединение может жить
            // даже если endpoint вышел из зоны видимости при discovery
          }
        },
        serviceId: serviceId,
      );
      print("🔍 Discovery: $_isDiscovering");
      return _isDiscovering;
    } catch (e) {
      print("Ошибка discovery: $e");
      _isDiscovering = false;
      return false;
    }
  }

  // --- ТАЙМЕРЫ ---
  void _startTimers() {
    _pingTimer?.cancel();
    _meshHealthTimer?.cancel();

    // Пинг каждые 15 сек
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final endpoints = List<String>.from(appState.connectedEndpoints.keys);
      for (final ep in endpoints) {
        _sendPacket(ep, {
          'type': 'ping',
          'uid': appState.uid,
          'name': appState.name.isNotEmpty ? appState.name : appState.uid,
        });
      }

      // Чистим мёртвых пиров (45 сек без pong)
      final now = DateTime.now();
      final dead = appState.peerLastSeen.entries
          .where((e) => now.difference(e.value).inSeconds > 45)
          .map((e) => e.key)
          .toList();
      for (final uid in dead) {
        appState.markPeerOfflineByUid(uid);
      }
    });

    // Health-check каждые 30 сек: перезапускаем advertising и discovery если упали
    _meshHealthTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      print("🔄 Health-check...");

      if (!_isAdvertising) {
        print("🔄 Перезапуск advertising...");
        await _doStartAdvertising();
      }

      // Discovery всегда перезапускаем — Android его тихо убивает
      print("🔄 Перезапуск discovery...");
      await _doStartDiscovery();
    });
  }

  // --- UI РАДАР ---
  Future<bool> startDiscovery(
    void Function(String, String, String) onDeviceFound,
  ) async {
    if (!await requestPermissions()) return false;
    _onDeviceFoundCallback = onDeviceFound;
    if (_isDiscovering) return true;
    return _doStartDiscovery();
  }

  void stopDiscoveryOnly() {
    _onDeviceFoundCallback = null;
    // Фоновый поиск продолжается — не останавливаем
  }

  // --- РУЧНОЕ ПОДКЛЮЧЕНИЕ ИЗ РАДАРА ---
  Future<void> connectToDevice(String endpointId) async {
    if (appState.connectedEndpoints.containsKey(endpointId)) return;
    if (_pendingNames.containsKey(endpointId)) return;
    if (_outgoingRequests.contains(endpointId)) return;

    // При ручном подключении из радара — игнорируем правило "кто меньше"
    _outgoingRequests.add(endpointId);
    try {
      final myName = appState.name.isNotEmpty ? appState.name : appState.uid;
      await Nearby().requestConnection(
        myName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      print("Ручной коннект $endpointId: $e");
      _outgoingRequests.remove(endpointId);
    }
  }

  // --- ОТПРАВКА СООБЩЕНИЯ ---
  bool sendMessage(String endpointId, String message) {
    return _sendPacket(endpointId, {
      'type': 'msg',
      'uid': appState.uid,
      'text': message,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'id': '${DateTime.now().millisecondsSinceEpoch}',
    });
  }

  void stopMesh() {
    _pingTimer?.cancel();
    _meshHealthTimer?.cancel();
    try { Nearby().stopAdvertising(); } catch (_) {}
    try { Nearby().stopDiscovery(); } catch (_) {}
    _isAdvertising = false;
    _isDiscovering = false;
    _pendingNames.clear();
    _outgoingRequests.clear();
  }
}

final meshService = MeshService();