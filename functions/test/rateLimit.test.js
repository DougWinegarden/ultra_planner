const test = require("node:test");
const assert = require("node:assert");
const {
  RATE_LIMIT_MAX,
  RATE_LIMIT_WINDOW_MS,
  evaluateRateLimit,
} = require("../rateLimit");

const NOW = 1_700_000_000_000;

test("a first-time caller is allowed and starts a window", () => {
  const verdict = evaluateRateLimit(null, NOW);
  assert.equal(verdict.allowed, true);
  assert.equal(verdict.next.count, 1);
  assert.equal(verdict.next.windowStart, NOW);
});

test("a caller under the limit keeps the same window", () => {
  const verdict = evaluateRateLimit({count: 5, windowStart: NOW - 1000}, NOW);
  assert.equal(verdict.allowed, true);
  assert.equal(verdict.next.count, 6);
  assert.equal(verdict.next.windowStart, NOW - 1000);
});

test("the last call inside the allowance is still allowed", () => {
  const verdict = evaluateRateLimit(
    {count: RATE_LIMIT_MAX - 1, windowStart: NOW},
    NOW,
  );
  assert.equal(verdict.allowed, true);
  assert.equal(verdict.next.count, RATE_LIMIT_MAX);
});

test("hitting the limit is refused", () => {
  const verdict = evaluateRateLimit(
    {count: RATE_LIMIT_MAX, windowStart: NOW},
    NOW,
  );
  assert.equal(verdict.allowed, false);
  assert.ok(verdict.retryInSec > 0);
});

test("an elapsed window resets the count", () => {
  const verdict = evaluateRateLimit(
    {count: RATE_LIMIT_MAX, windowStart: NOW - RATE_LIMIT_WINDOW_MS - 1},
    NOW,
  );
  assert.equal(verdict.allowed, true);
  assert.equal(verdict.next.count, 1);
  assert.equal(verdict.next.windowStart, NOW);
});

test("the window boundary itself resets rather than blocking forever", () => {
  const verdict = evaluateRateLimit(
    {count: RATE_LIMIT_MAX, windowStart: NOW - RATE_LIMIT_WINDOW_MS},
    NOW,
  );
  assert.equal(verdict.allowed, true);
});

test("retry advice never reads as zero seconds", () => {
  // One millisecond left on the window: naive rounding would floor to 0.
  const verdict = evaluateRateLimit(
    {count: RATE_LIMIT_MAX, windowStart: NOW - RATE_LIMIT_WINDOW_MS + 1},
    NOW,
  );
  assert.equal(verdict.allowed, false);
  assert.ok(verdict.retryInSec >= 1, `got ${verdict.retryInSec}`);
});

test("a corrupt counter does not lock a user out", () => {
  const verdict = evaluateRateLimit({count: "nonsense"}, NOW);
  assert.equal(verdict.allowed, true);
  assert.equal(verdict.next.count, 1);
});
