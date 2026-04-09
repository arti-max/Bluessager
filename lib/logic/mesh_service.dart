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

  // Пинг-таймер: каждые 15 сек проверяем живые соединения
  Timer? _pingTimer;
  // Авто-сканирование для друзей: каждые 30 сек
  Timer? _friendScanTimer;

  // Колбэк для UI радара (только когда активен)
  void Function(String, String, String)? _onDeviceFoundCallback;

  // --- РАЗРЕШЕНИЯ ---
  Future<bool> requestPermissions() async {
    PermissionStatus locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted) return false;

    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
    ].request();

    final hasBasic = statuses[Permission.bluetooth]?.isGranted == true;
    final hasNew = statuses[Permission.bluetoothConnect]?.isGranted == true &&
        statuses[Permission.bluetoothScan]?.isGranted == true &&
        statuses[Permission.bluetoothAdvertise]?.isGranted == true;

    return hasBasic || hasNew;
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
        // Ответить pong — подтверждаем что живы
        _sendPacket(endpointId, {'type': 'pong', 'uid': appState.uid});
        // Обновить имя пира если пришло в пинге
        final senderUid = data['uid'] as String?;
        if (senderUid != null) {
          appState.connectedEndpoints[endpointId] = senderUid;
          appState.peerNames[senderUid] = data['name'] as String? ?? senderUid;
          appState.notifyConnectionChange();
        }
      } else if (type == 'pong') {
        // Пинг получил ответ — пир живой, обновляем метку времени
        final senderUid = data['uid'] as String?;
        if (senderUid != null) {
          appState.connectedEndpoints[endpointId] = senderUid;
          appState.peerLastSeen[senderUid] = DateTime.now();
          appState.notifyConnectionChange();
        }
      }
    } catch (e) {
      // Не JSON — старый формат, пробуем как plain text
      print("Пакет не JSON, игнорируем: $e");
    }
  }

  // --- ОТПРАВКА ПАКЕТА (внутренний) ---
  bool _sendPacket(String endpointId, Map<String, dynamic> data) {
    try {
      Nearby().sendBytesPayload(
        endpointId,
        Uint8List.fromList(utf8.encode(jsonEncode(data))),
      );
      return true;
    } catch (e) {
      print("Ошибка пакета: $e");
      return false;
    }
  }

  // --- ОБЩИЕ ОБРАБОТЧИКИ СОЕДИНЕНИЯ ---
  void _onConnectionInitiated(String? endpointId, ConnectionInfo info) {
    if (endpointId == null) return;

    Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: _handlePayload,
      onPayloadTransferUpdate: (id, update) {},
    );

    // Регистрируем под endpointId пока не придёт ping с реальным UID
    appState.onPeerConnected(endpointId, endpointId, info.endpointName);

    // Сразу шлём пинг чтобы обменяться UID
    Future.delayed(const Duration(milliseconds: 500), () {
      _sendPacket(endpointId, {
        'type': 'ping',
        'uid': appState.uid,
        'name': appState.name.isNotEmpty ? appState.name : appState.uid,
      });
    });
  }

  void _onConnectionResult(String? endpointId, Status status) {
    print("Соединение $endpointId: $status");
  }

  void _onDisconnected(String? endpointId) {
    if (endpointId != null) appState.onPeerDisconnected(endpointId);
  }

  // --- ПИНГ-ТАЙМЕР (фоновая проверка живости) ---
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final endpoints = List<String>.from(appState.connectedEndpoints.keys);
      for (final endpointId in endpoints) {
        final ok = _sendPacket(endpointId, {
          'type': 'ping',
          'uid': appState.uid,
          'name': appState.name.isNotEmpty ? appState.name : appState.uid,
        });
        if (!ok) {
          // Не удалось — пир умер
          appState.onPeerDisconnected(endpointId);
        }
      }

      // Чистим пиров которых не видели > 45 сек
      final now = DateTime.now();
      final deadPeers = appState.peerLastSeen.entries
          .where((e) => now.difference(e.value).inSeconds > 45)
          .map((e) => e.key)
          .toList();
      for (final uid in deadPeers) {
        appState.markPeerOfflineByUid(uid);
      }
    });
  }

  // --- ТАЙМЕР СКАНИРОВАНИЯ ДРУЗЕЙ (фон, без UI) ---
  void _startFriendScanTimer() {
    _friendScanTimer?.cancel();
    _friendScanTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_isDiscovering) {
        await _startDiscoveryInternal();
      }
    });
  }

  // --- ЗАПУСК ВСЕГО (вызывается при старте приложения) ---
  Future<void> startMeshNode() async {
    if (!await requestPermissions()) {
      print("Нет прав — mesh не запущен");
      return;
    }

    // Параллельно запускаем раздачу и поиск
    await startAdvertising();
    await _startDiscoveryInternal();
    _startPingTimer();
    _startFriendScanTimer();

    print("Mesh-узел запущен");
  }

  // --- РАЗДАЧА (beacon) ---
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
      print("Реклама: $_isAdvertising");
      return _isAdvertising;
    } catch (e) {
      print("Ошибка рекламы: $e");
      return false;
    }
  }

  // --- ПОИСК ВНУТРЕННИЙ (без UI колбэка, только для авто-коннекта к друзьям) ---
  Future<bool> _startDiscoveryInternal() async {
    if (_isDiscovering) return true;

    try {
      _isDiscovering = await Nearby().startDiscovery(
        appState.name.isNotEmpty ? appState.name : appState.uid,
        strategy,
        onEndpointFound: (endpointId, endpointName, svcId) {
          if (endpointId == null || endpointName == null) return;

          // Сообщаем UI радара если он активен
          _onDeviceFoundCallback?.call(endpointId, endpointId, endpointName);

          // Авто-коннект к другу (по имени, т.к. UID пока не знаем до пинга)
          // Подключаемся ко всем, кого нашли — после пинга разберём кто друг
          if (!appState.connectedEndpoints.containsKey(endpointId)) {
            _autoConnect(endpointId);
          }
        },
        onEndpointLost: (endpointId) {
          if (endpointId != null) appState.onPeerDisconnected(endpointId);
        },
        serviceId: serviceId,
      );
      return _isDiscovering;
    } catch (e) {
      print("Ошибка поиска: $e");
      _isDiscovering = false;
      return false;
    }
  }

  // --- ПОИСК ДЛЯ РАДАРА (с UI колбэком) ---
  Future<bool> startDiscovery(
    void Function(String, String, String) onDeviceFound,
  ) async {
    if (!await requestPermissions()) return false;

    _onDeviceFoundCallback = onDeviceFound;

    if (_isDiscovering) return true; // Уже ищем — просто добавили колбэк

    return _startDiscoveryInternal();
  }

  void stopDiscoveryOnly() {
    _onDeviceFoundCallback = null; // Убираем UI колбэк, но поиск продолжается в фоне
    // НЕ останавливаем реальный Nearby discovery — он нужен для друзей
    print("UI радар выключен, фоновый поиск продолжается");
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

  // --- РУЧНОЕ ПОДКЛЮЧЕНИЕ (из радара) ---
  Future<void> connectToDevice(String endpointId) async {
    if (appState.connectedEndpoints.containsKey(endpointId)) {
      print("Уже подключены к $endpointId");
      return;
    }
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
  }
}

final meshService = MeshService();