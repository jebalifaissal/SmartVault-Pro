class ClassificationRequest {
  const ClassificationRequest({
    required this.id,
    required this.userEmail,
    required this.title,
    required this.documentType,
    required this.createdAt,
    this.message,
  });

  final String id;
  final String userEmail;
  final String title;
  final String documentType;
  final DateTime createdAt;
  final String? message;

  factory ClassificationRequest.fromApi(Map<String, dynamic> data) {
    final id = data['id'];
    final userEmail = data['user_email'];
    final title = data['title'];
    final documentType = data['document_type'];
    final createdAt = data['created_at'];
    final message = data['message'];
    if (id is! String ||
        userEmail is! String ||
        title is! String ||
        documentType is! String ||
        createdAt is! String ||
        DateTime.tryParse(createdAt) == null ||
        (message != null && message is! String)) {
      throw const FormatException('Demande de classification invalide.');
    }
    return ClassificationRequest(
      id: id,
      userEmail: userEmail,
      title: title,
      documentType: documentType,
      createdAt: DateTime.parse(createdAt),
      message: message as String?,
    );
  }
}

class ClassificationDecision {
  const ClassificationDecision({
    required this.id,
    required this.status,
    this.securityLevel,
    this.category,
    this.rejectionReason,
  });

  final String id;
  final String status;
  final String? securityLevel;
  final String? category;
  final String? rejectionReason;
}
