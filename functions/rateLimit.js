/**
 * Per-user rate limiting for the Gemini proxy.
 *
 * Split out from index.js so the decision itself is a pure function: it takes
 * the stored counter and the current time and returns what should happen, with
 * no Firestore involved. That makes the window-rollover and boundary cases
 * testable without an emulator.
 */

/** Requests allowed per user inside one window. */
const RATE_LIMIT_MAX = 30;

/** Length of the rate limit window, in milliseconds. */
const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;

/**
 * Decides whether one call is allowed.
 *
 * @param {object|null} data Stored counter: {count, windowStart}, or null when
 *     this user has never called before.
 * @param {number} now Current time in epoch milliseconds.
 * @return {{allowed: boolean, retryInSec?: number,
 *     next?: {count: number, windowStart: number}}}
 *     When allowed, `next` is the counter state to persist.
 */
function evaluateRateLimit(data, now) {
  const windowStart =
    data && typeof data.windowStart === "number" ? data.windowStart : 0;

  // A window that has fully elapsed starts over, which also covers the
  // never-called case where windowStart is 0.
  const expired = now - windowStart >= RATE_LIMIT_WINDOW_MS;
  const count = expired ? 0 : (data && data.count) || 0;

  if (count >= RATE_LIMIT_MAX) {
    return {
      allowed: false,
      // Always at least a second, so the message never says "0 seconds".
      retryInSec: Math.max(
        1,
        Math.ceil((windowStart + RATE_LIMIT_WINDOW_MS - now) / 1000),
      ),
    };
  }

  return {
    allowed: true,
    next: {count: count + 1, windowStart: expired ? now : windowStart},
  };
}

module.exports = {
  RATE_LIMIT_MAX,
  RATE_LIMIT_WINDOW_MS,
  evaluateRateLimit,
};
