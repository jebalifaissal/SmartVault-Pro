# Document photo analysis

The photo and import flows require explicit consent before sending a document
image to an external AI service. The Runware Qwen2.5-VL function suggests the
document category and extracts the holder name, document number, and expiry
date. A separate Gemini function extracts the given name, surname, date of
birth, and place of birth from a national ID card. The user must review any
extracted values. Document metadata is saved in Firestore and photos are stored
in Firebase Storage.

## Setup

1. Select the Firebase project associated with the app:

   ```powershell
   firebase use --add
   ```

2. In the Firebase console, create a Firestore database and enable Firebase
   Storage. Cloud Functions deployment may require the Blaze billing plan.
3. Deploy the Firestore and Storage rules:

   ```powershell
   firebase deploy --only firestore:rules,storage
   ```

4. Enable Cloud Functions in the Firebase console. Cloud Functions deployment
   may require the Blaze billing plan.
5. Revoke any API key that has been shared in chat, logs, or source control,
   then create replacement keys. Configure each as a Firebase secret. Never
   put an API key in Flutter, `pubspec.yaml`, or a checked-in `.env` file:

   ```powershell
   firebase functions:secrets:set RUNWARE_API_KEY
   firebase functions:secrets:set GEMINI_API_KEY
   ```

6. Deploy the callables:

   ```powershell
   firebase deploy --only functions:classifyDocumentPhoto,functions:extractNationalIdFields,functions:classifyDocumentType,storage
   ```

All callables in `functions/index.js` require Firebase Authentication.
`classifyDocumentType` calls Gemini to return only one validated category:
`CIN`, `PASSPORT`, `CERTIFICATE`, `DRIVING_LICENSE`, or `OTHER`. Its request
and response validation are in `functions/src/gemini_document_classifier.js`;
shared JPEG/PNG and size validation is in `functions/src/image_validation.js`.
The Flutter HTTP service is `lib/services/ai_service.dart`; it sends the
Firebase ID token to this callable and never contains a Gemini API key.

The Runware request is implemented in `functions/src/runware_client.js`; Gemini
national-ID extraction and response validation are in
`functions/src/gemini_national_id_client.js`. The API keys remain server-side
in Firebase Secret Manager. The Flutter Gemini wrapper is
`lib/features/documents/data/firebase_gemini_national_id_extractor.dart`;
the camera flow uses it for national ID cards after obtaining the user's
consent. Extracted values are reviewed in the ID form and saved to the
Firestore document in the `identity` Storage folder. The extractor returns a
map with `name`, `surname`, `dateOfBirth` (YYYY-MM-DD), and `placeOfBirth`;
unavailable or unclear values are `null`. Firestore ownership rules are in
`firestore.rules`; Storage ownership rules are in `storage.rules`.

Run the backend unit tests with `npm test` from this directory.
