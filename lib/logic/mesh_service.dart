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

  // Общий обработчик входящих сообщений
  void _handlePayload(String endpointId, Payload payload) {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;
    final text = String.fromCharCodes(payload.bytes!);
    final peerUid = appState.connectedEndpoints[endpointId] ?? endpointId;
    appState.addMessage(
      peerUid,
      ChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        senderUid: peerUid,
        peerUid: peerUid,
        text: text,
        timestamp: DateTime.now(),
        isMe: false,
      ),
    );
  }

  Future<bool> requestPermissions() async {
    PermissionStatus locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted) return false;

    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.nearbyWifiDevices,
    ].request();

    bool hasBasicBluetooth = statuses[Permission.bluetooth]?.isGranted == true;
    bool hasNewBluetooth =
        statuses[Permission.bluetoothConnect]?.isGranted == true &&
        statuses[Permission.bluetoothScan]?.isGranted == true &&
        statuses[Permission.bluetoothAdvertise]?.isGranted == true;

    return hasBasicBluetooth || hasNewBluetooth;
  }

  Future<bool> startAdvertising() async {
    if (!await requestPermissions()) return false;

    try {
      return await Nearby().startAdvertising(
        appState.name.isEmpty ? appState.uid : appState.name,
        strategy,
        onConnectionInitiated: (String? endpointId, ConnectionInfo info) {
          if (endpointId == null) return;
          Nearby().acceptConnection(
            endpointId,
            onPayLoadRecieved: _handlePayload,
            onPayloadTransferUpdate: (id, update) {},
          );
          // ВОТ ГЛАВНЫЙ ФИX: регистрируем пира
          appState.onPeerConnected(endpointId, endpointId, info.endpointName);
        },
        onConnectionResult: (String? endpointId, Status status) {
          print("Advertising result: $status");
        },
        onDisconnected: (String? endpointId) {
          if (endpointId != null) appState.onPeerDisconnected(endpointId);
        },
        serviceId: serviceId,
      );
    } catch (e) {
      print("Ошибка раздачи: $e");
      return false;
    }
  }

  Future<bool> startDiscovery(
    void Function(String, String, String) onDeviceFound,
  ) async {
    if (!await requestPermissions()) return false;

    try {
      return await Nearby().startDiscovery(
        appState.name.isEmpty ? appState.uid : appState.name,
        strategy,
        onEndpointFound: (String? endpointId, String? endpointName, String? svcId) {
          if (endpointId == null || endpointName == null) return;
          onDeviceFound(endpointId, endpointId, endpointName);
        },
        onEndpointLost: (String? endpointId) {
          if (endpointId != null) appState.onPeerDisconnected(endpointId);
        },
        serviceId: serviceId,
      );
    } catch (e) {
      print("Ошибка поиска: $e");
      return false;
    }
  }

  Future<void> connectToDevice(String endpointId) async {
    try {
      await Nearby().requestConnection(
        appState.name.isEmpty ? appState.uid : appState.name,
        endpointId,
        onConnectionInitiated: (String? id, ConnectionInfo info) {
          if (id == null) return;
          Nearby().acceptConnection(
            id,
            onPayLoadRecieved: _handlePayload,
            onPayloadTransferUpdate: (epId, update) {},
          );
          // ВОТ ГЛАВНЫЙ ФИX: регистрируем пира
          appState.onPeerConnected(id, id, info.endpointName);
        },
        onConnectionResult: (String? id, Status status) {
          print("Connect result: $status");
        },
        onDisconnected: (String? id) {
          if (id != null) appState.onPeerDisconnected(id);
        },
      );
    } catch (e) {
      print("Ошибка подключения: $e");
    }
  }

  bool sendMessage(String endpointId, String message) {
    try {
      Nearby().sendBytesPayload(
        endpointId,
        Uint8List.fromList(message.codeUnits),
      );
      return true;
    } catch (e) {
      print("Ошибка отправки: $e");
      return false;
    }
  }

  void stopDiscoveryOnly() {
    Nearby().stopDiscovery();
  }

  void stopMesh() {
    Nearby().stopAdvertising();
    Nearby().stopDiscovery();
  }
}

final meshService = MeshService();