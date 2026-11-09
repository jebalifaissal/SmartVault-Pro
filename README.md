# SmartVault Pro

Application Flutter Android de gestion sécurisée de documents personnels.

## Backend Cloudflare

L’application utilise le Worker Cloudflare et D1 pour l’authentification, les
sessions, les documents et les demandes de classification. Aucun SDK Firebase
n’est utilisé par l’application.

Les migrations D1 existantes se trouvent dans `cloudflare-backend/migrations`.
Pour générer les types après un changement de configuration et déployer :

```powershell
Set-Location .\cloudflare-backend
npx.cmd wrangler d1 migrations apply smartvault-db --remote
npx.cmd wrangler types
npx.cmd wrangler deploy
```

Les comptes sont créés par l’écran d’inscription. L’accès Admin doit être
provisionné séparément dans D1; l’inscription publique ne peut pas attribuer ce
rôle. La réinitialisation du mot de passe répondra « indisponible » jusqu’à ce
qu’un service d’envoi d’e-mails soit configuré.

Après avoir créé un compte avec une adresse autorisée, un opérateur Cloudflare
peut lui accorder le rôle Admin dans D1 :

```powershell
npx.cmd wrangler d1 execute smartvault-db --remote --command "INSERT INTO admin_users (email, user_id) SELECT email, id FROM auth_users WHERE email = 'admin@example.com' ON CONFLICT(email) DO UPDATE SET user_id = excluded.user_id, active = 1"
```

Les métadonnées des documents et les sessions sont stockées dans D1. Les
photos des demandes de classification ne sont pas stockées; l’API photo Admin
répond explicitement que cette fonctionnalité n’est pas disponible.

Pour démarrer l’application Flutter :

```powershell
flutter run
```

Pour tester avec Wrangler local et l’émulateur Android, lancer `npm.cmd run dev`
dans `cloudflare-backend`, puis démarrer Flutter dans un second terminal :

```powershell
flutter run --dart-define=SMARTVAULT_API_BASE_URL=http://10.0.2.2:8787
```

Les documents D1 existants sans propriétaire ne sont pas visibles par les
comptes; attribuez-les explicitement avant de les supprimer.

## Ajout d’une CIN

Depuis le portefeuille, **Ajouter un document > Ajouter une CIN** ouvre la
caméra, analyse localement la photo avec Tesseract français/arabe, puis
présente une confirmation. Le bouton **Oui, confirmer** sauvegarde la photo
dans le répertoire privé de l’application et enregistre ses champs dans
SQLite, sans envoyer la CIN à un service distant. Les lignes SQLite sont
partitionnées par l’identifiant de la session connectée. Le portefeuille
combine les documents Cloudflare et les CIN locales; ces dernières restent
visibles même sans réseau.

Les moteurs et modèles OCR sont locaux (`fra` et `ara`). Les champs non lus
restent vides; la confirmation signifie uniquement que l’utilisateur accepte
les informations extraites, et ne constitue pas une vérification officielle de
son identité. Les données OCR ne sont pas écrites dans les logs.

Le dépôt local, son schéma SQLite et la gestion du fichier image sont dans
`lib/features/documents/data/sqflite_local_cin_repository.dart`. Ses tests de
persistance, d’isolation par utilisateur, de nouvelle tentative et de
suppression sont dans `test/local_cin_repository_test.dart`.

## Verrouillage après inactivité

Les écrans privés se verrouillent après une minute sans interaction tactile ou
clavier. L’application se verrouille aussi quand elle passe en arrière-plan.
Pour reprendre, l’utilisateur confirme son mot de passe auprès du Worker
Cloudflare; une erreur laisse l’écran verrouillé. La déconnexion reste
disponible.

- `lib/features/auth/presentation/auth_gate.dart` applique la protection à la
  session authentifiée.
- `lib/features/auth/presentation/idle_session_gate.dart` observe l’activité,
  le cycle de vie Android et présente l’écran de verrouillage.
- `lib/features/auth/domain/auth_repository.dart` définit la réauthentification.
- `lib/features/auth/data/cloudflare_auth_repository.dart` la vérifie auprès
  du Worker Cloudflare.

Les tests de cette règle sont dans `test/widget_test.dart`. Le délai peut être
ajusté avec le paramètre `idleTimeout` d’`AuthGate`.
"# SmartVault-Pro" 
