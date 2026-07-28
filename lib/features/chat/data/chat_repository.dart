import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/chat_message.dart';

/// Customer↔mower chat for a live job. Reads go direct against `messages`
/// (RLS-scoped to the two participants + admins, so realtime streaming just
/// works); writes go through the `send_message` RPC so every message is
/// off-app/cash flag-scanned server-side before it lands.
class ChatRepository {
  SupabaseClient get _client => Supabase.instance.client;

  static const _cols = 'id, sender_id, sender_role, body, flagged, created_at';

  /// Live thread for a booking, oldest first.
  Stream<List<ChatMessage>> stream(String bookingId) {
    final myId = _client.auth.currentUser?.id;
    return _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('booking_id', bookingId)
        .order('created_at')
        .map((rows) => rows
            .map((r) => ChatMessage.fromRow(Map<String, dynamic>.from(r),
                myId: myId))
            .toList());
  }

  /// One-shot fetch (fallback / initial paint).
  Future<List<ChatMessage>> fetch(String bookingId) async {
    final myId = _client.auth.currentUser?.id;
    final rows = await _client
        .from('messages')
        .select(_cols)
        .eq('booking_id', bookingId)
        .order('created_at');
    return (rows as List)
        .map((r) =>
            ChatMessage.fromRow(Map<String, dynamic>.from(r as Map), myId: myId))
        .toList();
  }

  /// Sends a message. Returns nothing useful to the caller on purpose — the
  /// server-side flag result is intentionally not exposed to the sender.
  Future<void> send(String bookingId, String body) async {
    await _client.rpc('send_message',
        params: {'p_booking_id': bookingId, 'p_body': body});
  }

  /// Whether the chat channel is currently open (mower en route → in progress).
  Future<bool> isOpen(String bookingId) async {
    final res =
        await _client.rpc('chat_open', params: {'p_booking_id': bookingId});
    return res == true;
  }
}

final chatRepositoryProvider =
    Provider<ChatRepository>((ref) => ChatRepository());
