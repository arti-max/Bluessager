enum MessageStatus { pending, sent, delivered }

class ChatMessage {
  final String id;
  final String senderUid;
  final String peerUid;      // UID собеседника (ключ истории)
  final String text;
  final DateTime timestamp;
  final bool isMe;
  MessageStatus status;

  ChatMessage({
    required this.id,
    required this.senderUid,
    required this.peerUid,
    required this.text,
    required this.timestamp,
    required this.isMe,
    this.status = MessageStatus.sent,
  });
}