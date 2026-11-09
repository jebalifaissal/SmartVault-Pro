/// Représente l'administrateur authentifié.
class AdminUser {
  const AdminUser({
    required this.email,
    required this.role,
  });

  final String email;
  final String role; // toujours 'admin'

  factory AdminUser.fromApi(Map<String, dynamic> data) {
    final email = data['email'];
    final role = data['role'];
    if (email is! String || email.isEmpty || role is! String) {
      throw const FormatException('Réponse admin invalide.');
    }
    return AdminUser(email: email, role: role);
  }
}
