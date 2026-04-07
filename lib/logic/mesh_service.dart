import 'dart:typed_data';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_state.dart';

class MeshService {
  static final MeshService _instance = MeshService._internal();
  factory MeshService() => _instance;
  MeshService._internal();

  final Strategy strategy = Strategy.P2P_CLUSTER;
  final String serviceId = "com.bluessager.mesh";

  // --- УЛУЧШЕННЫЙ ЗАПРОС РАЗРЕШЕНИЙ ---
  Future<bool> requestPermissions() async {
    // 1. Сначала запрашиваем через стандартный пакет
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);

    // 2. Обязательно проверяем, включен ли вообще ползунок геолокации в телефоне!
    bool locationEnabled = await Nearby().checkLocationEnabled();
    if (!locationEnabled) {
      print("ОШИБКА: Геолокация ВЫКЛЮЧЕНА в шторке телефона!");
      return false;
    }

    // 3. Используем встроенные методы библиотеки для уверенности
    bool hasLocationPerm = await Nearby().checkLocationPermission();
    if (!hasLocationPerm) {
      await Nearby().askLocationPermission();
    }

    // Проверка разрешений для Bluetooth (только Android 12+)
    bool hasBluetoothPerm = await Nearby().checkBluetoothPermission();
    if (!hasBluetoothPerm) {
      Nearby().askBluetoothPermission();
    }

    return allGranted && locationEnabled;
  }

  // --- 1. НАЧАТЬ РАЗДАЧУ ---
  Future<bool> startAdvertising() async {
    bool hasPermissions = await requestPermissions();
    if (!hasPermissions) {
      print("Нет прав для старта раздачи");
      return false;
    }

    try {
      bool result = await Nearby().startAdvertising(
        appState.name.isEmpty ? appState.uid : appState.name,
        strategy,
        onConnectionInitiated: (String? endpointId, ConnectionInfo info) {
          if (endpointId == null) return;
          print("Подключение от: ${info.endpointName}");
          
          Nearby().acceptConnection(
            endpointId,
            onPayLoadRecieved: (String endpointId, Payload payload) {
              if (payload.type == PayloadType.BYTES && payload.bytes != null) {
                String msg = String.fromCharCodes(payload.bytes!);
                print("Сообщение от $endpointId: $msg");
              }
            },
            onPayloadTransferUpdate: (String endpointId, PayloadTransferUpdate payloadTransferUpdate) {},
          );
        },
        onConnectionResult: (String? endpointId, Status status) {
          print("Результат подключения: $status");
        },
        onDisconnected: (String? endpointId) {
          print("ОТКЛЮЧЕНО: $endpointId");
        },
        serviceId: serviceId,
      );
      print("Старт раздачи: УСПЕХ = $result");
      return result;
    } catch (e) {
      print("Ошибка старта раздачи: $e");
      return false;
    }
  }

  // --- 2. ИСКАТЬ ДРУГИХ ---
  Future<bool> startDiscovery(Function(String, String) onDeviceFound) async {
    bool hasPermissions = await requestPermissions();
    if (!hasPermissions) {
      print("Нет прав для старта поиска");
      return false;
    }

    try {
      bool result = await Nearby().startDiscovery(
        appState.name.isEmpty ? appState.uid : appState.name,
        strategy,
        onEndpointFound: (String? endpointId, String? endpointName, String? serviceId) {
          if (endpointId == null || endpointName == null) return;
          print("Найден: $endpointName ($endpointId)");
          onDeviceFound(endpointId, endpointName);
        },
        onEndpointLost: (String? endpointId) {
          print("Потерян: $endpointId");
        },
        serviceId: serviceId,
      );
      print("Старт поиска: УСПЕХ = $result");
      return result;
    } catch (e) {
      print("Ошибка старта поиска: $e");
      return false;
    }
  }

  // --- 3. ПОДКЛЮЧЕНИЕ ---
  Future<void> connectToDevice(String endpointId) async {
    try {
      await Nearby().requestConnection(
        appState.name.isEmpty ? appState.uid : appState.name,
        endpointId,
        onConnectionInitiated: (String? id, ConnectionInfo info) {
          if (id == null) return;
          Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (String endpointId, Payload payload) {},
            onPayloadTransferUpdate: (String endpointId, PayloadTransferUpdate payloadTransferUpdate) {},
          );
        },
        onConnectionResult: (String? id, Status status) {
          print("Результат подключения: $status");
        },
        onDisconnected: (String? id) {},
      );
    } catch (e) {
      print("Ошибка подключения: $e");
    }
  }

  void sendMessage(String endpointId, String message) {
    Nearby().sendBytesPayload(endpointId, Uint8List.fromList(message.codeUnits));
  }

  void stopDiscoveryOnly() {
    Nearby().stopDiscovery();
    print("Поиск остановлен");
  }

  void stopMesh() {
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
    print("Mesh-сеть полностью остановлена");
  }
}

final meshService = MeshService();