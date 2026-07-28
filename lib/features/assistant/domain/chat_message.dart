/// One turn in the assistant conversation. Only `user` and `assistant` turns
/// are sent to the backend as history; the role strings match the Claude
/// Messages API (and the `assistant` edge function filters to exactly these).
class ChatMessage {
  const ChatMessage({required this.role, required this.text});

  const ChatMessage.user(this.text) : role = 'user';
  const ChatMessage.assistant(this.text) : role = 'assistant';

  final String role; // 'user' | 'assistant'
  final String text;

  bool get isUser => role == 'user';

  Map<String, String> toJson() => {'role': role, 'content': text};
}

/// The backend's answer: text to show plus an optional client action. Today the
/// only action is `start_booking` — the assistant hands the customer off to the
/// app's booking flow (map-draw + payment stay in the UI, money human-in-loop).
class AssistantReply {
  const AssistantReply({required this.reply, this.action});

  final String reply;
  final String? action; // e.g. 'start_booking'

  bool get startsBooking => action == 'start_booking';
}
