/**
 * Ocean Lists -- Gemini proxy.
 *
 * The app used to hold a Gemini API key on the client. That key was readable by
 * anyone with console access and extractable from the running app. This
 * function replaces that: the key lives in Secret Manager, only ever inside the
 * function, and the client sends a question rather than a credential.
 *
 * Because one key now serves every user, the function requires a signed-in
 * caller and rate limits per account -- otherwise anyone with an account could
 * drain the project's quota.
 */

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {defineSecret, defineString} = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");
const {evaluateRateLimit} = require("./rateLimit");

admin.initializeApp();
const db = admin.firestore();

/**
 * Set with:  firebase functions:secrets:set GEMINI_API_KEY
 * Never commit the value -- it is injected at runtime, not stored in source.
 */
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

/**
 * Model id, overridable without a code change:
 *   firebase functions:config  is deprecated; set this in .env or via
 *   `firebase deploy` params. Defaults to a current flash-lite model.
 */
const GEMINI_MODEL = defineString("GEMINI_MODEL", {
  default: "gemini-2.5-flash-lite",
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

exports.askQuackers = onCall(
  {
    secrets: [GEMINI_API_KEY],
    region: "us-central1",
    // Keeps a single user's burst from spinning up unbounded instances.
    maxInstances: 10,
    timeoutSeconds: 60,
  },
  async (request) => {
    // 1. Only signed-in users. This is what stops the key being a free
    //    for-all now that it is shared.
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Please log in before chatting with Quackers.",
      );
    }
    const uid = request.auth.uid;

    // 2. Validate input before spending quota on it.
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

    // 3. Per-user throttle.
    await enforceRateLimit(uid);

    // 4. Call Gemini. The key is read here and never leaves the function.
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
          "x-goog-api-key": GEMINI_API_KEY.value(),
        },
        body: JSON.stringify({
          systemInstruction: {
            parts: [{text: `${SYSTEM_PROMPT}\n\nTASK CONTEXT:\n${taskContext}`}],
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
      // Log the real reason for the developer; return something safe to the
      // client, since upstream messages can echo request details.
      logger.error("Gemini returned an error", {
        status: response.status,
        body: body,
      });

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
