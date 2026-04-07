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

  // --- ЖЕЛЕЗОБЕТОННЫЙ ЗАПРОС РАЗРЕШЕНИЙ (ИСПРАВЛЕННЫЙ ДЛЯ ANDROID 12) ---
  Future<bool> requestPermissions() async {
    // 1. Сначала принудительно запрашиваем точную локацию (Критично для Android 12)
    PermissionStatus locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted) {
      print("ОШИБКА: Пользователь отказал в доступе к локации");
      return false;
    }

    // 2. Затем запрашиваем все Bluetooth и Wi-Fi права
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
    ].request();

    // 3. Анализируем ответы без жесткой привязки ко всем сразу
    bool hasBasicBluetooth = statuses[Permission.bluetooth]?.isGranted == true;
    
    // Новые блютуз-права (появились в Android 12)
    bool hasNewBluetooth = (statuses[Permission.bluetoothConnect]?.isGranted == true) && 
                           (statuses[Permission.bluetoothScan]?.isGranted == true) &&
                           (statuses[Permission.bluetoothAdvertise]?.isGranted == true);
    
    // Если нам дали ЛИБО старый блютуз (Android 11 и ниже), ЛИБО новый блютуз (Android 12 и выше)
    if (hasBasicBluetooth || hasNewBluetooth) {
      return true;
    } else {
      print("ОШИБКА РАЗРЕШЕНИЙ BLUETOOTH");
      print("Basic BT: $hasBasicBluetooth");
      print("New BT: $hasNewBluetooth");
      return false;
    }
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