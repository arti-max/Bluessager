class AppState {
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal();

  // Настройки профиля
  String uid = "MESH-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";
  String name = "";
  bool isGatewayEnabled = true;
  bool isMaskingEnabled = false;

  // Теперь друзья — это объекты (словари)
  List<Map<String, dynamic>> friends = [
    {"uid": "MESH-12345", "name": "Иван"},
    {"uid": "MESH-67890", "name": ""} // У этого пользователя нет имени
  ];
  
  List<Map<String, dynamic>> groups = [
    {"name": "Секретная группа", "members": 2}
  ];
}

final appState = AppState();