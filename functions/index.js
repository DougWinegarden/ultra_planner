/**
 * Ocean Lists -- Gemini proxy with per-user API keys.
 *
 * Each user brings their own Gemini key. The key is sent once to saveGeminiKey,
 * encrypted with AES-256-GCM, and stored as ciphertext in Firestore. It is
 * decrypted only inside askQuackers, for the duration of one Gemini call.
 *
 * What this buys over storing the key directly:
 *   - Firestore holds ciphertext, so the console, an export, or a leaked
 *     backup shows nothing usable
 *   - the key is never in the app bundle, on the device, or readable back by
 *     the client -- the app can ask *whether* a key is set, never what it is
 *   - security rules deny clients all access to the stored record
 *
 * What it does not buy: anyone who can read the master secret can decrypt every
 * stored key. A proxy has to recover the plaintext to call Gemini, so that is
 * unavoidable. See crypto.js.
 */

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret, defineString} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {evaluateRateLimit} = require("./rateLimit");
const {encryptApiKey, decryptApiKey, keyHint} = require("./crypto");

admin.initializeApp();
const db = admin.firestore();

/**
 * Set with:  firebase functions:secrets:set GEMINI_API_KEY
 * Never commit the value -- it is injected at runtime, not stored in source.
 */
/**
 * Master key used to encrypt every user's Gemini key. Generate and set with:
 *
 *   openssl rand -base64 32
 *   firebase functions:secrets:set GEMINI_KEY_ENCRYPTION_KEY
 *
 * Rotating this invalidates every stored key: users re-enter theirs.
 */
const ENCRYPTION_KEY = defineSecret("GEMINI_KEY_ENCRYPTION_KEY");

/** Model id, overridable via functions/.env without a code change. */
const GEMINI_MODEL = defineString("GEMINI_MODEL", {
  default: "gemini-3.5-flash-lite",
});

// --- Limits -----------------------------------------------------------------

/** Rejects oversized prompts before they reach Gemini. */
const MAX_QUESTION_CHARS = 2000;
const MAX_CONTEXT_CHARS = 8000;
/** Most recent turns to forward; keeps the request bounded. */
const MAX_HISTORY_TURNS = 20;

const SYSTEM_PROMPT =
  "You are Quackers, a warm, playful capybara in a duck suit. Answer the " +
  "user's questions helpfully, including general questions, while also being " +
  "a great task-planning buddy. Use only the task context below for claims " +
  "about the user's tasks. For task or planning questions, give short, " +
  "practical advice and prioritize one next action when asked. Never pretend " +
  "to have completed a task. Do not refuse a normal, safe question merely " +
  "because it is unrelated to tasks. Keep answers to five short sentences or " +
  "fewer unless the user asks for more detail. Always finish your final " +
  "sentence; never end mid-sentence.";

/**
 * Throws if this user has spent their allowance for the current window.
 *
 * Runs in a transaction so simultaneous calls from the same account cannot both
 * read the same count and slip past the limit.
 *
 * @param {string} uid Caller's Firebase Auth uid.
 */
async function enforceRateLimit(uid) {
  const ref = db.collection("rateLimits").doc(uid);
  const now = Date.now();

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const verdict = evaluateRateLimit(snap.exists ? snap.data() : null, now);

    if (!verdict.allowed) {
      throw new HttpsError(
        "resource-exhausted",
        `Quackers is taking a breather. Try again in ` +
          `${verdict.retryInSec} seconds.`,
      );
    }

    tx.set(
      ref,
      {
        count: verdict.next.count,
        windowStart: verdict.next.windowStart,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  });
}

/**
 * Builds the Gemini `contents` array from the conversation so far.
 *
 * @param {Array} conversation Prior turns, oldest first.
 * @param {string} question The new user message.
 * @return {Array} Gemini-shaped contents.
 */
function buildContents(conversation, question) {
  const history = Array.isArray(conversation) ?
    conversation.slice(-MAX_HISTORY_TURNS) :
    [];

  const contents = history
    .filter((m) => m && typeof m.text === "string" && m.text.trim() !== "")
    .map((m) => ({
      role: m.isUser ? "user" : "model",
      parts: [{text: String(m.text)}],
    }));

  contents.push({role: "user", parts: [{text: question}]});
  return contents;
}

// --- Stored key access ------------------------------------------------------

/**
 * Firestore location of one user's encrypted key.
 *
 * Clients are denied all access to this path in firestore.rules; only the
 * Admin SDK inside these functions reads or writes it.
 *
 * @param {string} uid Firebase Auth uid.
 * @return {FirebaseFirestore.DocumentReference} The settings document.
 */
function keyDoc(uid) {
  return db.collection("users").doc(uid).collection("private").doc("settings");
}

/**
 * Rejects the call unless it carries a signed-in user.
 *
 * @param {object} request The callable request.
 * @return {string} The caller's uid.
 */
function requireUid(request) {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Please log in before using Quackers.",
    );
  }
  return request.auth.uid;
}

// --- Callables --------------------------------------------------------------

/**
 * Stores the caller's Gemini API key, encrypted.
 *
 * The plaintext exists only for the life of this call: it arrives over TLS, is
 * encrypted, and is never written anywhere in the clear, including logs.
 */
exports.saveGeminiKey = onCall(
  {secrets: [ENCRYPTION_KEY], region: "us-central1", maxInstances: 5},
  async (request) => {
    const uid = requireUid(request);
    const raw = request.data && request.data.apiKey;

    if (typeof raw !== "string" || raw.trim() === "") {
      throw new HttpsError("invalid-argument", "Enter your Gemini API key.");
    }
    const apiKey = raw.trim();
    if (apiKey.length > 200) {
      throw new HttpsError(
        "invalid-argument",
        "That does not look like a Gemini API key.",
      );
    }

    let record;
    try {
      record = encryptApiKey(apiKey, ENCRYPTION_KEY.value());
    } catch (error) {
      // A misconfigured master key is an operator problem, not a user one.
      // parseMasterKey's messages say which of the two it is and never contain
      // key material, so they are safe to surface rather than flatten.
      logger.error("Could not encrypt API key", error);
      throw new HttpsError(
        "failed-precondition",
        `Server setup problem: ${error.message}`,
      );
    }

    await keyDoc(uid).set(
      {
        geminiKey: record,
        geminiKeyHint: keyHint(apiKey),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    return {saved: true, hint: keyHint(apiKey)};
  },
);

/**
 * Reports whether the caller has a key saved, without revealing it.
 *
 * Lets the app open straight to the chat or the setup panel instead of finding
 * out by sending a message that fails.
 */
exports.quackersStatus = onCall(
  {region: "us-central1", maxInstances: 5},
  async (request) => {
    const uid = requireUid(request);
    const snap = await keyDoc(uid).get();
    const data = snap.exists ? snap.data() : null;

    return {
      hasKey: Boolean(data && data.geminiKey && data.geminiKey.cipher),
      // Only ever the last four characters, so the user can tell which key is
      // saved without the key itself leaving the server.
      hint: (data && data.geminiKeyHint) || null,
    };
  },
);

/** Removes the caller's stored key. */
exports.deleteGeminiKey = onCall(
  {region: "us-central1", maxInstances: 5},
  async (request) => {
    const uid = requireUid(request);
    await keyDoc(uid).set(
      {
        geminiKey: admin.firestore.FieldValue.delete(),
        geminiKeyHint: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    return {deleted: true};
  },
);

/** Answers a question as Quackers, using the caller's own Gemini key. */
exports.askQuackers = onCall(
  {
    secrets: [ENCRYPTION_KEY],
    region: "us-central1",
    // Bounded so a runaway client cannot spend the project's budget.
    maxInstances: 10,
    timeoutSeconds: 60,
  },
  async (request) => {
    const uid = requireUid(request);

    // 1. Validate input before doing any work on it.
    const data = request.data || {};
    const question = typeof data.question === "string" ?
      data.question.trim() :
      "";
    const taskContext = typeof data.taskContext === "string" ?
      data.taskContext.slice(0, MAX_CONTEXT_CHARS) :
      "";

    if (question === "") {
      throw new HttpsError("invalid-argument", "Ask Quackers a question.");
    }
    if (question.length > MAX_QUESTION_CHARS) {
      throw new HttpsError(
        "invalid-argument",
        `Question is too long (max ${MAX_QUESTION_CHARS} characters).`,
      );
    }

    // 2. Throttle per account. Each user spends their own Gemini quota, but
    //    every call still costs this project a function invocation.
    await enforceRateLimit(uid);

    // 3. Recover this user's key. Plaintext lives only in this scope.
    const snap = await keyDoc(uid).get();
    const stored = snap.exists ? snap.data() : null;
    if (!stored || !stored.geminiKey) {
      throw new HttpsError(
        "failed-precondition",
        "Add your Gemini API key to start chatting with Quackers.",
      );
    }

    let apiKey;
    try {
      apiKey = decryptApiKey(stored.geminiKey, ENCRYPTION_KEY.value());
    } catch (error) {
      // Usually means the master key was rotated out from under stored data.
      logger.error("Could not decrypt stored key", {uid: uid, error: error});
      throw new HttpsError(
        "failed-precondition",
        "Your saved key could not be read. Please enter it again.",
      );
    }

    // 4. Call Gemini.
    const model = GEMINI_MODEL.value();
    const endpoint =
      "https://generativelanguage.googleapis.com/v1beta/models/" +
      `${model}:generateContent`;

    let response;
    try {
      response = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": apiKey,
        },
        body: JSON.stringify({
          systemInstruction: {
            parts: [
              {text: `${SYSTEM_PROMPT}\n\nTASK CONTEXT:\n${taskContext}`},
            ],
          },
          contents: buildContents(data.conversation, question),
          generationConfig: {
            maxOutputTokens: 2048,
            thinkingConfig: {thinkingLevel: "minimal"},
          },
        }),
      });
    } catch (error) {
      logger.error("Gemini request failed to send", error);
      throw new HttpsError(
        "unavailable",
        "Could not reach Quackers. Please try again.",
      );
    }

    const body = await response.json().catch(() => ({}));

    if (!response.ok) {
      // Log the real reason for the operator; hand the user something safe,
      // since upstream messages can echo request details.
      logger.error("Gemini returned an error", {
        status: response.status,
        body: body,
      });

      if (response.status === 400 || response.status === 403) {
        // Almost always a bad or revoked key -- the one thing the user can fix.
        throw new HttpsError(
          "permission-denied",
          "Gemini rejected your API key. Check it and enter it again.",
        );
      }
      if (response.status === 429 || response.status >= 500) {
        throw new HttpsError(
          "unavailable",
          "Quackers is busy right now. Please try again shortly.",
        );
      }
      if (response.status === 404) {
        throw new HttpsError(
          "failed-precondition",
          `The configured model (${model}) was not found. Update the ` +
            "GEMINI_MODEL parameter.",
        );
      }
      throw new HttpsError("internal", "Quackers could not answer that one.");
    }

    const text = body &&
      body.candidates &&
      body.candidates[0] &&
      body.candidates[0].content &&
      body.candidates[0].content.parts &&
      body.candidates[0].content.parts[0] &&
      body.candidates[0].content.parts[0].text;

    if (typeof text !== "string" || text.trim() === "") {
      logger.warn("Gemini returned no usable text", {body: body});
      throw new HttpsError(
        "internal",
        "Quackers did not have anything to say. Please try again.",
      );
    }

    return {text: text.trim()};
  },
);
