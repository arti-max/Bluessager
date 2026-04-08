import 'dart:async';
import 'package:flutter/material.dart';
import '../logic/app_state.dart';
import '../logic/mesh_service.dart';
import '../models/chat_message.dart';

class ChatScreen extends StatefulWidget {
  final String peerUid;
  final String peerName;
  final bool isGroup;

  const ChatScreen({super.key, required this.peerUid, required this.peerName, this.isGroup = false,});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late List<ChatMessage> _messages;
  StreamSubscription<ChatMessage>? _msgSub;
  StreamSubscription<void>? _connSub;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _messages = List.from(appState.getHistory(widget.peerUid));
    _isConnected = appState.isPeerConnected(widget.peerUid);

    _msgSub = appState.messageStream.listen((msg) {
      if (msg.peerUid == widget.peerUid && !msg.isMe) {
        if (mounted) setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    });

    _connSub = appState.connectionStream.listen((_) {
      if (mounted) setState(() {
        _isConnected = appState.isPeerConnected(widget.peerUid);
      });
      // После переподключения — обновляем статусы pending сообщений
      _refreshMessageStatuses();
    });

    // Ловим события, которые могли прилететь ДО подписки
    Future.microtask(() {
      if (mounted) setState(() => _isConnected = appState.isPeerConnected(widget.peerUid));
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _connSub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final msg = ChatMessage(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      senderUid: appState.uid,
      peerUid: widget.peerUid,
      text: text,
      timestamp: DateTime.now(),
      isMe: true,
      status: MessageStatus.pending,
    );

    if (!widget.isGroup) {
      // Личный чат
      final endpointId = appState.getEndpointForPeer(widget.peerUid);
      if (endpointId != null) {
        final ok = meshService.sendMessage(endpointId, text);
        msg.status = ok ? MessageStatus.delivered : MessageStatus.pending;
      }
      // Офлайн — просто pending, сообщение уходит в историю без return
    } else {
      // Группа — рассылаем всем подключённым прямо сейчас
      bool anySent = false;
      for (final endpointId in appState.connectedEndpoints.keys) {
        if (meshService.sendMessage(endpointId, text)) anySent = true;
      }
      msg.status = anySent ? MessageStatus.delivered : MessageStatus.pending;
    }

    appState.addMessage(widget.peerUid, msg);
    if (mounted) {
      setState(() {
        _messages.add(msg);
        _controller.clear();
      });
    }
    _scrollToBottom();
  }

  // Добавить этот метод (вызывается из _connSub)
  void _refreshMessageStatuses() {
    if (!mounted) return;
    setState(() {
      _messages = List.from(appState.getHistory(widget.peerUid));
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(DateTime dt) =>
      "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.peerName, style: const TextStyle(fontSize: 16)),
            Row(children: [
              Icon(
                Icons.circle,
                size: 8,
                color: _isConnected ? Colors.greenAccent : Colors.grey,
              ),
              const SizedBox(width: 4),
              Text(
                _isConnected ? 'Онлайн' : 'Офлайн',
                style: TextStyle(
                  fontSize: 12,
                  color: _isConnected ? Colors.greenAccent : Colors.grey,
                ),
              ),
            ]),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 52, color: Colors.grey[700]),
                        const SizedBox(height: 12),
                        Text(
                          'Сообщения хранятся только\nна вашем устройстве',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) => _buildBubble(_messages[i]),
                  ),
          ),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    return Align(
      alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: msg.isMe ? Colors.deepPurple[700] : Colors.grey[800],
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(msg.isMe ? 18 : 4),
            bottomRight: Radius.circular(msg.isMe ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg.text, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(msg.timestamp),
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.55)),
                ),
                if (msg.isMe) ...[
                  const SizedBox(width: 3),
                  Icon(
                    msg.status == MessageStatus.delivered ? Icons.done_all : Icons.done,
                    size: 13,
                    color: msg.status == MessageStatus.delivered
                        ? Colors.greenAccent
                        : Colors.white38,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file, color: Colors.grey),
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Файлы через Wi-Fi Direct — скоро')),
            ),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: const InputDecoration(
                hintText: 'Сообщение...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.deepPurpleAccent),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}