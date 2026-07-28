/// One line in a booking's customer↔mower thread.
///
/// `flagged` is set server-side by `send_message` when the text hints at taking
/// the job off-app; it is deliberately NOT surfaced to the sender in the UI —
/// only admins see it — so a bad actor isn't tipped off.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderRole,
    required this.body,
    required this.createdAt,
    required this.isMine,
    this.flagged = false,
  });

  final String id;
  final String senderRole; // 'customer' | 'mower'
  final String body;
  final DateTime createdAt;
  final bool isMine;
  final bool flagged;

  factory ChatMessage.fromRow(Map<String, dynamic> r, {String? myId}) {
    return ChatMessage(
      id: r['id'] as String,
      senderRole: (r['sender_role'] as String?) ?? 'customer',
      body: (r['body'] as String?) ?? '',
      flagged: r['flagged'] as bool? ?? false,
      createdAt: DateTime.tryParse(r['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isMine: myId != null && r['sender_id'] == myId,
    );
  }
}
