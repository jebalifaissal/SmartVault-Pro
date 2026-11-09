const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { defineSecret } = require("firebase-functions/params");
const { getApps, initializeApp } = require("firebase-admin/app");
const {
  FieldValue,
  Timestamp,
  getFirestore,
} = require("firebase-admin/firestore");
const { analyzeDocument } = require("./src/runware_client");
const { decodeImage } = require("./src/image_validation");
const { classifyDocument } = require("./src/gemini_document_classifier");
const {
  extractNationalIdFields,
} = require("./src/gemini_national_id_client");
const {
  createShareToken,
  readActiveShare,
  sanitizeShareFields,
  validateExpirationMinutes,
} = require("./src/document_sharing");

const runwareApiKey = defineSecret("RUNWARE_API_KEY");
const geminiApiKey = defineSecret("GEMINI_API_KEY");
const shareCollection = "documentShares";

if (getApps().length === 0) initializeApp();
const firestore = getFirestore();

function requireAuthenticatedUser(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Connexion requise.");
  }
  return request.auth.uid;
}

function invalidShareRequest(error) {
  if (error instanceof TypeError) {
    throw new HttpsError("invalid-argument", error.message);
  }
  throw error;
}

function getValidatedImage(data) {
  try {
    return decodeImage(data ?? {});
  } catch {
    throw new HttpsError(
      "invalid-argument",
      "Image invalide. Choisissez une photo JPEG ou PNG de 6 Mo maximum.",
    );
  }
}

exports.classifyDocumentPhoto = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 90,
    memory: "512MiB",
    maxInstances: 3,
    secrets: [runwareApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }

    const { imageBase64, mimeType } = getValidatedImage(request.data);

    try {
      return await analyzeDocument({
        apiKey: runwareApiKey.value(),
        imageBase64,
        mimeType,
      });
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        "unavailable",
        "L’analyse IA est momentanément indisponible. Réessayez plus tard.",
      );
    }
  },
);

exports.extractNationalIdFields = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 90,
    memory: "512MiB",
    maxInstances: 3,
    secrets: [geminiApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }

    const { imageBase64, mimeType } = getValidatedImage(request.data);

    try {
      return await extractNationalIdFields({
        apiKey: geminiApiKey.value(),
        imageBase64,
        mimeType,
      });
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        "unavailable",
        "L’extraction Gemini est momentanément indisponible.",
      );
    }
  },
);

exports.classifyDocumentType = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 90,
    memory: "512MiB",
    maxInstances: 3,
    secrets: [geminiApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Connexion requise.");
    }

    const { imageBase64, mimeType } = getValidatedImage(request.data);
    try {
      return await classifyDocument({
        apiKey: geminiApiKey.value(),
        imageBase64,
        mimeType,
      });
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      throw new HttpsError(
        "unavailable",
        "La classification Gemini est momentanément indisponible.",
      );
    }
  },
);

exports.createDocumentShare = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 30,
    maxInstances: 10,
  },
  async (request) => {
    const ownerUid = requireAuthenticatedUser(request);
    let fields;
    let durationMinutes;
    try {
      fields = sanitizeShareFields(request.data?.fields);
      durationMinutes = validateExpirationMinutes(
        request.data?.durationMinutes,
      );
    } catch (error) {
      invalidShareRequest(error);
    }

    const documentId = request.data?.documentId;
    if (typeof documentId !== "string" || documentId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "Document invalide.");
    }

    const { token, tokenHash } = createShareToken();
    const shareRef = firestore.collection(shareCollection).doc();
    const expiresAt = Timestamp.fromMillis(
      Date.now() + durationMinutes * 60 * 1000,
    );
    await shareRef.create({
      ownerUid,
      documentId: documentId.trim(),
      tokenHash,
      fields,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt,
    });

    return {
      shareId: shareRef.id,
      token,
      expiresAtMillis: expiresAt.toMillis(),
    };
  },
);

exports.listDocumentShares = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 30,
    maxInstances: 10,
  },
  async (request) => {
    const ownerUid = requireAuthenticatedUser(request);
    const documentId = request.data?.documentId;
    if (typeof documentId !== "string" || documentId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "Document invalide.");
    }

    const snapshot = await firestore
      .collection(shareCollection)
      .where("ownerUid", "==", ownerUid)
      .limit(100)
      .get();
    return {
      shares: snapshot.docs
        .filter((doc) => doc.data().documentId === documentId)
        .map((doc) => {
          const data = doc.data();
          return {
            shareId: doc.id,
            createdAtMillis: data.createdAt?.toMillis?.() ?? null,
            expiresAtMillis: data.expiresAt.toMillis(),
            status: data.expiresAt.toMillis() <= Date.now()
              ? "expired"
              : "active",
          };
        }),
    };
  },
);

exports.revokeDocumentShare = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 30,
    maxInstances: 10,
  },
  async (request) => {
    const ownerUid = requireAuthenticatedUser(request);
    const shareId = request.data?.shareId;
    if (typeof shareId !== "string" || shareId.trim().length === 0) {
      throw new HttpsError("invalid-argument", "Partage invalide.");
    }

    const shareRef = firestore.collection(shareCollection).doc(shareId);
    await firestore.runTransaction(async (transaction) => {
      const share = await transaction.get(shareRef);
      if (!share.exists || share.data().ownerUid !== ownerUid) {
        throw new HttpsError("not-found", "Partage introuvable.");
      }
      transaction.delete(shareRef);
    });
    return { revoked: true };
  },
);

const shareViewerHtml = `<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="referrer" content="no-referrer">
  <title>Document partagé - SmartVault Pro</title>
  <style>
    body{font:16px system-ui,sans-serif;background:#f4f7f7;color:#172b3a;margin:0;padding:24px}
    main{max-width:560px;margin:8vh auto;background:white;padding:24px;border-radius:18px}
    h1{font-size:22px} dt{font-weight:700;margin-top:18px;color:#087e78}
    dd{margin:5px 0 0;overflow-wrap:anywhere} #status{color:#71808a}
  </style>
</head>
<body>
  <main><h1>Document partagé</h1><p id="status">Vérification du partage…</p><dl id="fields"></dl></main>
  <script>
    const statusNode=document.getElementById("status");
    const fieldsNode=document.getElementById("fields");
    const token=new URLSearchParams(location.hash.slice(1)).get("token");
    history.replaceState(null,"",location.pathname);
    if(!token){statusNode.textContent="Lien de partage invalide.";throw new Error("Missing token");}
    fetch(location.pathname,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({token})})
      .then(async response=>{if(!response.ok)throw new Error("inactive");return response.json();})
      .then(result=>{
        statusNode.textContent="Informations partagées temporairement par le propriétaire.";
        const labels={category:"Catégorie",holderName:"Titulaire",firstName:"Prénom",lastName:"Nom",documentNumber:"Numéro",dateOfBirth:"Date de naissance",placeOfBirth:"Lieu de naissance",expirationDate:"Date d’expiration"};
        for(const [key,value] of Object.entries(result.fields)){
          const term=document.createElement("dt");term.textContent=labels[key]||"Information";
          const detail=document.createElement("dd");detail.textContent=value;
          fieldsNode.append(term,detail);
        }
      })
      .catch(()=>{statusNode.textContent="Ce partage est expiré, révoqué ou invalide.";});
  </script>
</body>
</html>`;

exports.openDocumentShare = onRequest(
  {
    region: "us-central1",
    timeoutSeconds: 30,
    maxInstances: 20,
  },
  async (request, response) => {
    response.set("Cache-Control", "no-store, max-age=0");
    response.set("Referrer-Policy", "no-referrer");
    response.set("X-Content-Type-Options", "nosniff");
    response.set(
      "Content-Security-Policy",
      "default-src 'none'; script-src 'unsafe-inline'; connect-src 'self'; " +
        "style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; " +
        "frame-ancestors 'none'",
    );

    if (request.method === "GET") {
      response.status(200).type("html").send(shareViewerHtml);
      return;
    }
    if (request.method !== "POST") {
      response.set("Allow", "GET, POST").status(405).send();
      return;
    }

    const share = await readActiveShare({
      firestore,
      token: request.body?.token,
    });
    if (share.status === "expired") {
      response.status(410).json({ error: "Share expired." });
      return;
    }
    if (share.status !== "active") {
      response.status(404).json({ error: "Share not found." });
      return;
    }
    response.status(200).json({ fields: share.fields });
  },
);

exports.purgeExpiredDocumentShares = onSchedule(
  {
    schedule: "every 60 minutes",
    timeZone: "Etc/UTC",
    region: "us-central1",
    maxInstances: 1,
  },
  async () => {
    for (let batchNumber = 0; batchNumber < 4; batchNumber++) {
      const expiredShares = await firestore
        .collection(shareCollection)
        .where("expiresAt", "<=", Timestamp.now())
        .orderBy("expiresAt")
        .limit(450)
        .get();
      if (expiredShares.empty) return;

      const batch = firestore.batch();
      for (const share of expiredShares.docs) {
        batch.delete(share.ref);
      }
      await batch.commit();
    }
  },
);
