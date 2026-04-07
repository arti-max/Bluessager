import 'dart:typed_data';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_state.dart';

class MeshService {
  static final MeshService _instance = MeshService._internal();
  factory MeshService() => _instance;
  MeshService._internal();

  final Strategy strategy = Strategy.P2P_CLUSTER; // P2P_CLUSTER отлично подходит для Mesh-сетей (много ко многим)
  final String serviceId = "com.bluessager.mesh"; // Уникальный ID нашего мессенджера

  // Запрос разрешений у системы
  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  // 1. НАЧАТЬ РАЗДАЧУ (Я здесь, найдите меня!)
  Future<void> startAdvertising() async {
    bool hasPermissions = await requestPermissions();
    if (!hasPermissions) return;

    try {
      await Nearby().startAdvertising(
        appState.name.isEmpty ? appState.uid : appState.name, // Наше имя в сети
        strategy,
        onConnectionInitiated: (String endpointId, ConnectionInfo info) {
          // Кто-то хочет подключиться!
          print("Подключение от: ${info.endpointName}");
          // Автоматически принимаем соединение (в будущем можно добавить проверку по белому списку UID)
          Nearby().acceptConnection(
            endpointId,
            onPayLoadRecieved: (endpointId, payload) {
              // ПРИШЛО СООБЩЕНИЕ!
              if (payload.type == PayloadType.BYTES) {
                String msg = String.fromCharCodes(payload.bytes!);
                print("Сообщение от $endpointId: $msg");
                // TODO: передать сообщение в UI
              }
            },
            onPayloadTransferUpdate: (endpointId, payloadTransferUpdate) {},
          );
        },
        onConnectionResult: (String endpointId, Status status) {
          if (status == Status.CONNECTED) {
            print("УСПЕШНО ПОДКЛЮЧЕНО К $endpointId");
          }
        },
        onDisconnected: (String endpointId) {
          print("ОТКЛЮЧЕНО: $endpointId");
        },
        serviceId: serviceId,
      );
      print("Раздача начата!");
    } catch (e) {
      print("Ошибка раздачи: $e");
    }
  }

  // 2. ИСКАТЬ ДРУГИХ (Радар)
  Future<void> startDiscovery(Function(String, String) onDeviceFound) async {
    bool hasPermissions = await requestPermissions();
    if (!hasPermissions) return;

    try {
      await Nearby().startDiscovery(
        appState.name.isEmpty ? appState.uid : appState.name,
        strategy,
        onEndpointFound: (String endpointId, String endpointName, String serviceId) {
          print("Найден: $endpointName ($endpointId)");
          // Передаем найденное устройство в интерфейс
          onDeviceFound(endpointId, endpointName);
        },
        onEndpointLost: (String endpointId) {
          print("Потерян: $endpointId");
        },
        serviceId: serviceId,
      );
      print("Поиск начат!");
    } catch (e) {
      print("Ошибка поиска: $e");
    }
  }

  // 3. ПОДКЛЮЧИТЬСЯ К НАЙДЕННОМУ
  Future<void> connectToDevice(String endpointId) async {
    try {
      await Nearby().requestConnection(
        appState.name.isEmpty ? appState.uid : appState.name,
        endpointId,
        onConnectionInitiated: (id, info) {
          Nearby().acceptConnection(
            id,
            onPayLoadRecieved: (endpointId, payload) {},
            onPayloadTransferUpdate: (endpointId, payloadTransferUpdate) {},
          );
        },
        onConnectionResult: (id, status) {
          print("Результат подключения: $status");
        },
        onDisconnected: (id) {},
      );
    } catch (e) {
      print("Ошибка подключения: $e");
    }
  }

  // 4. ОТПРАВИТЬ СООБЩЕНИЕ
  void sendMessage(String endpointId, String message) {
    Nearby().sendBytesPayload(
      endpointId, 
      Uint8List.fromList(message.codeUnits)
    );
  }
}

final meshService = MeshService();