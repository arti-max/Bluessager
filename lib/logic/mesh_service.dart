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

  // 1. НАЧАТЬ РАЗДАЧУ
  Future<void> startAdvertising() async {
    bool hasPermissions = await requestPermissions();
    if (!hasPermissions) return;

    try {
      await Nearby().startAdvertising(
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
          if (status == Status.CONNECTED) {
            print("УСПЕШНО ПОДКЛЮЧЕНО К $endpointId");
          }
        },
        onDisconnected: (String? endpointId) {
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
        onEndpointFound: (String? endpointId, String? endpointName, String? serviceId) {
          if (endpointId == null || endpointName == null) return;
          print("Найден: $endpointName ($endpointId)");
          onDeviceFound(endpointId, endpointName);
        },
        onEndpointLost: (String? endpointId) { // ИСПРАВЛЕНА ОШИБКА ЗДЕСЬ (добавлен знак вопроса)
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

  // 4. ОТПРАВИТЬ СООБЩЕНИЕ
  void sendMessage(String endpointId, String message) {
    Nearby().sendBytesPayload(
      endpointId, 
      Uint8List.fromList(message.codeUnits)
    );
  }
}

final meshService = MeshService();