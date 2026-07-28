import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/chat_message.dart';

/// Talks to the `assistant` edge function, which runs the Claude tool-calling
/// loop server-side (support Q&A + record actions scoped to the signed-in
/// customer by RLS). The app never sees the API key and never runs the loop.
class AssistantRepository {
  SupabaseClient get _client => Supabase.instance.client;

  /// Sends the full visible history and returns the assistant's reply plus any
  /// client action. The conversation is stateless server-side, so we resend the
  /// history each turn (Messages API is stateless — same as the web SDK).
  Future<AssistantReply> send(List<ChatMessage> history) async {
    final res = await _client.functions.invoke('assistant', body: {
      'messages': history.map((m) => m.toJson()).toList(),
    });
    final data = res.data;
    if (data is! Map) {
      throw Exception('The assistant is unavailable right now.');
    }
    final error = data['error'];
    if (error != null) throw Exception(error.toString());
    return AssistantReply(
      reply: (data['reply'] as String?)?.trim().isNotEmpty == true
          ? data['reply'] as String
          : '…',
      action: (data['action'] as Map?)?['type'] as String?,
    );
  }
}

final assistantRepositoryProvider =
    Provider<AssistantRepository>((ref) => AssistantRepository());
