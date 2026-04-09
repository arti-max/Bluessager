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
  Timer? _friendScanTimer;

  void Function(String, String, String)? _onDeviceFoundCallback;

  // Храним имена пиров ДО подтверждения соединения
  // endpointId -> displayName из ConnectionInfo
  final Map<String, String> _pendingNames = {};

  // --- РАЗРЕШЕНИЯ ---
  Future<bool> requestPermissions() async {
    // Запрашиваем по одному — групповой запрос на Android 12 иногда глючит
    final loc = await Permission.locationWhenInUse.request();
    if (!loc.isGranted) {
      print("❌ Локация не выдана");
      return false;
    }

    final btScan      = await Permission.bluetoothScan.request();
    final btConnect   = await Permission.bluetoothConnect.request();
    final btAdvertise = await Permission.bluetoothAdvertise.request();
    final btClassic   = await Permission.bluetooth.request();

    // nearbyWifiDevices некритично — не блокируем если нет
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

  // --- ПАРСИНГ ВХОДЯЩИХ ПАКЕТОВ ---
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
          // Обновляем реальный UID пира (до этого был endpointId)
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
      print("Ошибка парсинга пакета: $e");
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

  // Шаг 1: Инициация — только принимаем и запоминаем имя
  void _onConnectionInitiated(String? endpointId, ConnectionInfo info) {
    if (endpointId == null) return;
    print("🤝 Инициация от ${info.endpointName} ($endpointId)");

    // Запоминаем имя — оно доступно только здесь
    _pendingNames[endpointId] = info.endpointName;

    // Принимаем соединение
    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: _handlePayload,
      onPayloadTransferUpdate: (id, update) {},
    );
  }

  // Шаг 2: Результат — здесь соединение реально установлено или упало
  void _onConnectionResult(String? endpointId, Status status) {
    if (endpointId == null) return;
    print("📶 Результат $endpointId: $status");

    if (status == Status.CONNECTED) {
      final displayName = _pendingNames.remove(endpointId) ?? endpointId;
      // Регистрируем под endpointId — реальный UID придёт через ping
      appState.onPeerConnected(endpointId, endpointId, displayName);

      // Шлём ping через 300мс чтобы обменяться реальными UID
      Future.delayed(const Duration(milliseconds: 300), () {
        _sendPacket(endpointId, {
          'type': 'ping',
          'uid': appState.uid,
          'name': appState.name.isNotEmpty ? appState.name : appState.uid,
        });
      });
    } else {
      // Ошибка или отказ
      _pendingNames.remove(endpointId);
      print("❌ Соединение не установлено: $status");
    }
  }

  void _onDisconnected(String? endpointId) {
    if (endpointId == null) return;
    print("🔌 Отключён: $endpointId");
    _pendingNames.remove(endpointId);
    appState.onPeerDisconnected(endpointId);
  }

  // --- ПИНГ-ТАЙМЕР ---
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final endpoints = List<String>.from(appState.connectedEndpoints.keys);
      for (final endpointId in endpoints) {
        _sendPacket(endpointId, {
          'type': 'ping',
          'uid': appState.uid,
          'name': appState.name.isNotEmpty ? appState.name : appState.uid,
        });
      }

      // Чистим мёртвых (нет pong > 45 сек)
      final now = DateTime.now();
      final dead = appState.peerLastSeen.entries
          .where((e) => now.difference(e.value).inSeconds > 45)
          .map((e) => e.key)
          .toList();
      for (final uid in dead) {
        appState.markPeerOfflineByUid(uid);
      }
    });
  }

  // --- ТАЙМЕР ПЕРЕСКАНИРОВАНИЯ ---
  void _startFriendScanTimer() {
    _friendScanTimer?.cancel();
    _friendScanTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_isDiscovering) {
        print("🔄 Перезапуск discovery...");
        await _startDiscoveryInternal();
      }
    });
  }

  // --- СТАРТ ВСЕГО УЗЛА ---
  Future<void> startMeshNode() async {
    if (!await requestPermissions()) {
      print("❌ Mesh не запущен — нет прав");
      return;
    }

    await startAdvertising();

    // Задержка критична: Nearby падает если advertising и discovery стартуют одновременно
    await Future.delayed(const Duration(milliseconds: 800));

    await _startDiscoveryInternal();

    _startPingTimer();
    _startFriendScanTimer();

    print("✅ Mesh-узел запущен");
  }

  // --- РАЗДАЧА ---
  Future<bool> startAdvertising() async {
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

  // --- ПОИСК ВНУТРЕННИЙ (фон) ---
  Future<bool> _startDiscoveryInternal() async {
    if (_isDiscovering) return true;

    try {
      _isDiscovering = await Nearby().startDiscovery(
        appState.name.isNotEmpty ? appState.name : appState.uid,
        strategy,
        onEndpointFound: (endpointId, endpointName, svcId) {
          if (endpointId == null || endpointName == null) return;
          print("👁 Найден: $endpointName ($endpointId)");

          // Уведомляем UI радара если активен
          _onDeviceFoundCallback?.call(endpointId, endpointId, endpointName);

          // Авто-коннект если ещё не подключены и не в процессе
          if (!appState.connectedEndpoints.containsKey(endpointId) &&
              !_pendingNames.containsKey(endpointId)) {
            _autoConnect(endpointId);
          }
        },
        onEndpointLost: (endpointId) {
          if (endpointId != null) {
            print("💨 Потерян: $endpointId");
            appState.onPeerDisconnected(endpointId);
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

  // --- ПОИСК ДЛЯ UI РАДАРА ---
  Future<bool> startDiscovery(
    void Function(String, String, String) onDeviceFound,
  ) async {
    if (!await requestPermissions()) return false;

    _onDeviceFoundCallback = onDeviceFound;

    // Если уже ищем в фоне — просто добавили колбэк, возвращаем успех
    if (_isDiscovering) return true;

    return _startDiscoveryInternal();
  }

  void stopDiscoveryOnly() {
    // Убираем только UI колбэк — фоновый поиск остаётся
    _onDeviceFoundCallback = null;
  }

  // --- АВТО-КОННЕКТ ---
  Future<void> _autoConnect(String endpointId) async {
    try {
      await Nearby().requestConnection(
        appState.name.isNotEmpty ? appState.name : appState.uid,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      print("Авто-коннект $endpointId: $e");
    }
  }

  // --- РУЧНОЕ ПОДКЛЮЧЕНИЕ ИЗ РАДАРА ---
  Future<void> connectToDevice(String endpointId) async {
    if (appState.connectedEndpoints.containsKey(endpointId)) return;
    if (_pendingNames.containsKey(endpointId)) return; // уже в процессе
    await _autoConnect(endpointId);
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
    _friendScanTimer?.cancel();
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    _isAdvertising = false;
    _isDiscovering = false;
    _pendingNames.clear();
  }
}

final meshService = MeshService();