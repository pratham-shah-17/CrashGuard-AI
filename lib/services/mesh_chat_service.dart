import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'mesh_network_service.dart';

class MeshMessage {
  final String senderId;
  final String content;
  final DateTime timestamp;

  MeshMessage({
    required this.senderId,
    required this.content,
    required this.timestamp,
  });
}

class MeshChatService extends StateNotifier<List<MeshMessage>> {
  final MeshNetworkService _meshService;
  StreamSubscription<MeshPacket>? _packetSub;

  MeshChatService(this._meshService) : super([]) {
    _listenForIncomingMessages();
  }

  void _listenForIncomingMessages() {
    _packetSub?.cancel();
    _packetSub = _meshService.packets.listen((packet) {
      final p = packet.payload;
      if (!p.startsWith('MSG:')) return;
      final content = p.substring(4).trim();
      if (content.isEmpty) return;
      receiveMessage(packet.senderId, content);
    });
  }

  Future<void> sendMessage(String content) async {
    final newMessage = MeshMessage(
      senderId: 'SELF',
      content: content,
      timestamp: DateTime.now(),
    );
    state = [...state, newMessage];

    // Broadcast via Mesh
    await _meshService.startBroadcasting('MSG:$content');
  }

  void receiveMessage(String sender, String content) {
    final newMessage = MeshMessage(
      senderId: sender,
      content: content,
      timestamp: DateTime.now(),
    );
    state = [...state, newMessage];
  }

  @override
  void dispose() {
    _packetSub?.cancel();
    super.dispose();
  }
}

final meshChatProvider =
    StateNotifierProvider.autoDispose<MeshChatService, List<MeshMessage>>((
      ref,
    ) {
      final mesh = ref.watch(meshNetworkServiceProvider);
      return MeshChatService(mesh);
    });
