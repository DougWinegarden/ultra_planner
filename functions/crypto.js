/**
 * Envelope encryption for user-supplied Gemini API keys.
 *
 * Each user's key is encrypted with AES-256-GCM before it is written to
 * Firestore, using one master key held in Secret Manager. Firestore therefore
 * stores ciphertext, not credentials: browsing the console, exporting the
 * database, or leaking a backup yields nothing usable.
 *
 * WHAT THIS DOES NOT PROTECT AGAINST: anyone who can read the master secret can
 * decrypt every stored key. That is unavoidable for a proxy -- the server has
 * to recover the plaintext to call Gemini. The guarantee is "not lying around
 * in plaintext", not "unreadable by the project owner".
 *
 * GCM is chosen over CBC because it authenticates: a tampered ciphertext fails
 * to decrypt instead of silently producing garbage.
 */

const crypto = require("node:crypto");

const ALGORITHM = "aes-256-gcm";
const KEY_BYTES = 32; // AES-256
const IV_BYTES = 12; // 96-bit nonce, the size GCM is specified for

/**
 * Parses the base64 master key from the environment.
 *
 * @param {string} rawBase64 Base64-encoded 32-byte key.
 * @return {Buffer} The raw key material.
 */
function parseMasterKey(rawBase64) {
  if (typeof rawBase64 !== "string" || rawBase64.trim() === "") {
    throw new Error(
      "Encryption key is not configured. Set the " +
        "GEMINI_KEY_ENCRYPTION_KEY secret -- see Part 5 of SETUP.md.",
    );
  }

  const key = Buffer.from(rawBase64.trim(), "base64");
  if (key.length !== KEY_BYTES) {
    throw new Error(
      `Encryption key must be ${KEY_BYTES} bytes once base64-decoded, ` +
        `got ${key.length}. Regenerate it with: openssl rand -base64 32`,
    );
  }
  return key;
}

/**
 * Encrypts a plaintext API key.
 *
 * A fresh random IV per call is what makes it safe to reuse one master key
 * across every user; reusing an IV with GCM would leak plaintext.
 *
 * @param {string} plaintext The user's Gemini API key.
 * @param {string} masterKeyBase64 Base64 master key.
 * @return {{cipher: string, iv: string, tag: string, v: number}} Stored record.
 */
function encryptApiKey(plaintext, masterKeyBase64) {
  if (typeof plaintext !== "string" || plaintext.trim() === "") {
    throw new Error("Cannot encrypt an empty API key.");
  }

  const key = parseMasterKey(masterKeyBase64);
  const iv = crypto.randomBytes(IV_BYTES);
  const cipher = crypto.createCipheriv(ALGORITHM, key, iv);

  const encrypted = Buffer.concat([
    cipher.update(plaintext.trim(), "utf8"),
    cipher.final(),
  ]);

  return {
    cipher: encrypted.toString("base64"),
    iv: iv.toString("base64"),
    tag: cipher.getAuthTag().toString("base64"),
    v: 1, // schema version, so a future re-encryption can be rolled out
  };
}

/**
 * Decrypts a stored record back into the API key.
 *
 * Throws if the record was tampered with or encrypted under a different master
 * key -- GCM's auth tag will not verify.
 *
 * @param {object} record Value produced by {@link encryptApiKey}.
 * @param {string} masterKeyBase64 Base64 master key.
 * @return {string} The plaintext API key.
 */
function decryptApiKey(record, masterKeyBase64) {
  if (!record || !record.cipher || !record.iv || !record.tag) {
    throw new Error("Stored key record is incomplete.");
  }

  const key = parseMasterKey(masterKeyBase64);
  const decipher = crypto.createDecipheriv(
    ALGORITHM,
    key,
    Buffer.from(record.iv, "base64"),
  );
  decipher.setAuthTag(Buffer.from(record.tag, "base64"));

  const decrypted = Buffer.concat([
    decipher.update(Buffer.from(record.cipher, "base64")),
    decipher.final(),
  ]);

  return decrypted.toString("utf8");
}

/**
 * Last four characters of a key, for showing the user which one is saved
 * without ever sending the key back to the client.
 *
 * @param {string} plaintext The API key.
 * @return {string} e.g. "...bQ8f".
 */
function keyHint(plaintext) {
  const trimmed = String(plaintext).trim();
  return trimmed.length <= 4 ? "..." : `...${trimmed.slice(-4)}`;
}

module.exports = {
  ALGORITHM,
  KEY_BYTES,
  IV_BYTES,
  parseMasterKey,
  encryptApiKey,
  decryptApiKey,
  keyHint,
};
