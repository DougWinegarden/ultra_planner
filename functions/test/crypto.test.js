const test = require("node:test");
const assert = require("node:assert");
const crypto = require("node:crypto");
const {
  encryptApiKey,
  decryptApiKey,
  parseMasterKey,
  keyHint,
} = require("../crypto");

const MASTER = crypto.randomBytes(32).toString("base64");
const OTHER_MASTER = crypto.randomBytes(32).toString("base64");
const API_KEY = "AIzaSyExampleKeyMaterial1234567890abcd";

test("a key round-trips through encrypt and decrypt", () => {
  const record = encryptApiKey(API_KEY, MASTER);
  assert.equal(decryptApiKey(record, MASTER), API_KEY);
});

test("the stored record never contains the plaintext", () => {
  const record = encryptApiKey(API_KEY, MASTER);
  const serialized = JSON.stringify(record);
  assert.ok(!serialized.includes(API_KEY));
  // Guard against a partial leak of the key material too.
  assert.ok(!serialized.includes(API_KEY.slice(0, 12)));
});

test("encrypting twice gives different ciphertext", () => {
  // A fixed IV would leak plaintext across users sharing the master key.
  const a = encryptApiKey(API_KEY, MASTER);
  const b = encryptApiKey(API_KEY, MASTER);
  assert.notEqual(a.cipher, b.cipher);
  assert.notEqual(a.iv, b.iv);
  assert.equal(decryptApiKey(a, MASTER), decryptApiKey(b, MASTER));
});

test("a different master key cannot decrypt", () => {
  const record = encryptApiKey(API_KEY, MASTER);
  assert.throws(() => decryptApiKey(record, OTHER_MASTER));
});

test("tampered ciphertext is rejected, not silently mangled", () => {
  const record = encryptApiKey(API_KEY, MASTER);
  const bytes = Buffer.from(record.cipher, "base64");
  bytes[0] = bytes[0] ^ 0xff;
  record.cipher = bytes.toString("base64");
  assert.throws(() => decryptApiKey(record, MASTER));
});

test("a tampered auth tag is rejected", () => {
  const record = encryptApiKey(API_KEY, MASTER);
  const tag = Buffer.from(record.tag, "base64");
  tag[0] = tag[0] ^ 0xff;
  record.tag = tag.toString("base64");
  assert.throws(() => decryptApiKey(record, MASTER));
});

test("an incomplete record is rejected", () => {
  assert.throws(() => decryptApiKey({cipher: "x"}, MASTER));
  assert.throws(() => decryptApiKey(null, MASTER));
});

test("a missing master key fails with actionable advice", () => {
  assert.throws(
    () => encryptApiKey(API_KEY, ""),
    /GEMINI_KEY_ENCRYPTION_KEY/,
  );
});

test("a wrong-length master key names the fix", () => {
  assert.throws(
    () => parseMasterKey(Buffer.from("too short").toString("base64")),
    /openssl rand -base64 32/,
  );
});

test("an empty api key is refused", () => {
  assert.throws(() => encryptApiKey("   ", MASTER));
});

test("surrounding whitespace is trimmed before storage", () => {
  const record = encryptApiKey(`  ${API_KEY}\n`, MASTER);
  assert.equal(decryptApiKey(record, MASTER), API_KEY);
});

test("keyHint shows only the last four characters", () => {
  assert.equal(keyHint(API_KEY), `...${API_KEY.slice(-4)}`);
  assert.ok(!keyHint(API_KEY).includes(API_KEY.slice(0, 8)));
});
