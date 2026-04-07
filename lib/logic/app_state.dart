// Глобальное состояние приложения (Singleton)
class AppState {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  // Настройки профиля
  String uid = "MESH-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
  String name = "";
  bool isGatewayEnabled = true;
  bool isMaskingEnabled = false;

  // Списки
  List<String> friends = ["MESH-12345 (Иван)"];
  List<Map<String, dynamic>> groups = [
    {"name": "Секретная группа", "members": 2}
  ];
}

// Удобная переменная для доступа из любого файла
final appState = AppState();