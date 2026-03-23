import 'package:uuid/uuid.dart';

/// Role of a participant in an AI chat session.
enum AiChatRole { user, assistant }

/// A single message stored in the [ai_chat_messages] SQLite table.
class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isCanvas = false,
    this.userId,
  });

  final String id;
  final String sessionId;
  final AiChatRole role;
  final String content;
  final DateTime createdAt;
  final bool isCanvas;
  final String? userId;

  static AiChatMessage create({
    required String sessionId,
    required AiChatRole role,
    required String content,
    bool isCanvas = false,
    String? userId,
  }) {
    return AiChatMessage(
      id: const Uuid().v4(),
      sessionId: sessionId,
      role: role,
      content: content,
      createdAt: DateTime.now(),
      isCanvas: isCanvas,
      userId: userId,
    );
  }

  factory AiChatMessage.fromMap(Map<String, dynamic> map) {
    return AiChatMessage(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      role: (map['role'] as String) == 'user'
          ? AiChatRole.user
          : AiChatRole.assistant,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      isCanvas: (map['is_canvas'] as int? ?? 0) == 1,
      userId: map['user_id'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'role': role == AiChatRole.user ? 'user' : 'assistant',
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'is_canvas': isCanvas ? 1 : 0,
      if (userId != null) 'user_id': userId,
    };
  }

  AiChatMessage copyWith({String? content, bool? isCanvas, String? userId}) {
    return AiChatMessage(
      id: id,
      sessionId: sessionId,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      isCanvas: isCanvas ?? this.isCanvas,
      userId: userId ?? this.userId,
    );
  }
}
