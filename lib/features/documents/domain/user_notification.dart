/// Notification envoyée à l'utilisateur suite à une décision admin.
class UserNotification {
  const UserNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.requestId,
    required this.isRead,
    required this.createdAt,
    this.category,
    this.securityLevel,
  });

  final String id;
  final String type; // 'document_accepted' | 'document_rejected'
  final String title;
  final String body;
  final String requestId;
  final bool isRead;
  final DateTime createdAt;
  final String? category;
  final String? securityLevel;

  bool get isAccepted => type == 'document_accepted';
  bool get isRejected => type == 'document_rejected';

  factory UserNotification.fromApi(Map<String, dynamic> data) {
    final id = data['id'];
    final type = data['type'];
    final title = data['title'];
    final body = data['body'];
    final requestId = data['request_id'];
    final isRead = data['is_read'];
    final createdAt = data['created_at'];
    if (id is! String ||
        type is! String ||
        title is! String ||
        body is! String ||
        requestId is! String ||
               (isRead is! bool && isRead is! int) ||
        createdAt is! int) {
      throw const FormatException('Notification invalide.');
    }
    return UserNotification(
      id: id,
      type: type,
      title: title,
      body: body,
      requestId: requestId,
            isRead: isRead == true || isRead == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      category: data['category'] as String?,
      securityLevel: data['security_level'] as String?,
    );
  }
}
