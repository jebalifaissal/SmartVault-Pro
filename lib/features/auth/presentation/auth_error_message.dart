import '../domain/auth_exception.dart';

String authErrorMessage(Object error) {
  if (error is! AuthException) {
    return 'Une erreur inattendue est survenue. Réessayez.';
  }

  final code = error.code;

  return switch (code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' ||
    'invalid-login-credentials' => 'Adresse e-mail ou mot de passe incorrect.',
    'requires-recent-login' =>
      'Reconnectez-vous pour confirmer votre identité.',
    'email-already-in-use' => 'Cette adresse e-mail est déjà utilisée.',
    'invalid-email' => 'Cette adresse e-mail n’est pas valide.',
    'weak-password' => 'Choisissez un mot de passe plus sécurisé.',
    'invalid-name' => 'Veuillez saisir un nom valide.',
    'user-disabled' => 'Ce compte a été désactivé.',
    'too-many-requests' => 'Trop de tentatives. Patientez avant de réessayer.',
    'registration-disabled' =>
      'La création de comptes sera activée après la configuration de la vérification e-mail.',
    'password-reset-disabled' =>
      'La réinitialisation sera activée après la configuration de l’envoi e-mail.',
    'network-request-failed' =>
      'Connexion réseau impossible. Vérifiez votre accès Internet.',
    'service-unavailable' =>
      'Le service de connexion est momentanément indisponible. Réessayez.',
    'operation-not-allowed' => 'Cette opération n’est pas disponible.',
    _ => 'La connexion a échoué. Réessayez dans un instant.',
  };
}
