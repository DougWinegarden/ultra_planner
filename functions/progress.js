/**
 * XP, levels, prestige and usernames.
 *
 * Levels follow the RuneScape experience curve: each level costs about 10%
 * more than the last, so level 92 is half of level 99. With the daily cap
 * below, a player who earns the cap every day reaches level 100 in about 90
 * days -- three months.
 *
 * XP is only ever awarded here, by the awardTaskXp trigger in index.js.
 * Clients cannot write profiles, so the leaderboard cannot be edited from the
 * app.
 *
 * Pure: no Firestore, so every rule is unit tested directly.
 */

const words = require("./usernameWords.json");

const MAX_LEVEL = 100;

/** Most XP one player can earn in a day: 89.9 days to level 100. */
const DAILY_XP_CAP = 160000;

/** A task with no length, or one of 30 minutes or less. */
const BASE_TASK_XP = 20000;

/** Added for each further half hour a task takes. */
const XP_PER_EXTRA_HALF_HOUR = 5000;

/** No single task is worth more than this, however long it claims to take. */
const MAX_TASK_XP = 40000;

/**
 * XP needed to reach each level, indexed by level. XP_TABLE[1] is 0.
 *
 * The RuneScape formula: the step from level n to n+1 costs
 * floor(n + 300 * 2^(n/7)) / 4 points.
 */
const XP_TABLE = (() => {
  const table = [0, 0];
  let points = 0;
  for (let level = 1; level < MAX_LEVEL; level++) {
    points += Math.floor(level + 300 * Math.pow(2, level / 7));
    table.push(Math.floor(points / 4));
  }
  return table;
})();

/**
 * @param {number} level 1 to MAX_LEVEL.
 * @return {number} Total XP needed to reach it.
 */
function xpForLevel(level) {
  return XP_TABLE[Math.max(1, Math.min(MAX_LEVEL, level))];
}

/**
 * The level a running XP total gives, capped at MAX_LEVEL. XP beyond level 100
 * is kept, not lost: it carries over when the player prestiges.
 *
 * @param {number} xp XP in the current prestige cycle.
 * @return {number} 1 to MAX_LEVEL.
 */
function levelForXp(xp) {
  let level = 1;
  while (level < MAX_LEVEL && XP_TABLE[level + 1] <= xp) level++;
  return level;
}

/**
 * What finishing a task is worth. Longer tasks are worth more, up to a limit.
 *
 * @param {number|null|undefined} durationMinutes The task's length, if set.
 * @return {number} XP.
 */
function taskXp(durationMinutes) {
  if (typeof durationMinutes !== "number" || !(durationMinutes > 30)) {
    return BASE_TASK_XP;
  }
  const extraHalfHours = Math.ceil((durationMinutes - 30) / 30);
  return Math.min(
    MAX_TASK_XP,
    BASE_TASK_XP + extraHalfHours * XP_PER_EXTRA_HALF_HOUR,
  );
}

// --- The XP day --------------------------------------------------------------

/**
 * @param {number} ms Instant, epoch milliseconds.
 * @param {string} timeZone IANA zone, e.g. "America/Los_Angeles".
 * @return {object} Wall-clock {y, m, d, h, mi, s} in that zone.
 */
function zonedParts(ms, timeZone) {
  const format = new Intl.DateTimeFormat("en-US", {
    timeZone: timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  const parts = {};
  for (const part of format.formatToParts(new Date(ms))) {
    parts[part.type] = Number(part.value);
  }
  return {
    y: parts.year,
    m: parts.month,
    d: parts.day,
    h: parts.hour,
    mi: parts.minute,
    s: parts.second,
  };
}

/**
 * @param {number} ms Instant, epoch milliseconds.
 * @param {string} timeZone IANA zone.
 * @return {number} How far that zone's wall clock is ahead of UTC, in ms.
 */
function zoneOffset(ms, timeZone) {
  const p = zonedParts(ms, timeZone);
  const wall = Date.UTC(p.y, p.m - 1, p.d, p.h, p.mi, p.s);
  return wall - Math.floor(ms / 1000) * 1000;
}

/**
 * The XP day an instant falls in, and when that day ends.
 *
 * Days are counted in one fixed zone for everyone. A per-device zone would let
 * a player shift their own midnight and collect the cap twice.
 *
 * @param {number} ms Instant, epoch milliseconds.
 * @param {string} timeZone IANA zone.
 * @return {{key: string, endsAt: number}} "YYYY-MM-DD", and the next local
 *     midnight as epoch milliseconds.
 */
function xpDay(ms, timeZone) {
  const p = zonedParts(ms, timeZone);
  const pad = (n) => String(n).padStart(2, "0");
  const nextMidnightWall = Date.UTC(p.y, p.m - 1, p.d + 1);
  // Guess with today's offset, then correct once in case a daylight-saving
  // change falls before midnight.
  let endsAt = nextMidnightWall - zoneOffset(ms, timeZone);
  endsAt = nextMidnightWall - zoneOffset(endsAt, timeZone);
  return {key: `${p.y}-${pad(p.m)}-${pad(p.d)}`, endsAt: endsAt};
}

// --- Awards and prestige -----------------------------------------------------

/**
 * A profile's progress fields with defaults filled in.
 *
 * @param {object|null|undefined} profile Stored profile, if any.
 * @return {object} {xp, totalXp, prestige, todayXp, xpDay}.
 */
function progressOf(profile) {
  const p = profile || {};
  const number = (value) => (typeof value === "number" && value >= 0 ?
    Math.floor(value) :
    0);
  return {
    xp: number(p.xp),
    totalXp: number(p.totalXp),
    prestige: number(p.prestige),
    todayXp: number(p.todayXp),
    xpDay: typeof p.xpDay === "string" ? p.xpDay : "",
  };
}

/**
 * Works out one task's award against the daily cap.
 *
 * @param {object|null} profile Stored profile, if any.
 * @param {number} value What the task is worth (taskXp).
 * @param {{key: string, endsAt: number}} day Result of xpDay for now.
 * @return {{award: number, update: object|null}} XP granted, and the profile
 *     fields to write, or null when nothing was granted.
 */
function applyAward(profile, value, day) {
  const current = progressOf(profile);
  const earnedToday = current.xpDay === day.key ? current.todayXp : 0;
  const award = Math.max(0, Math.min(value, DAILY_XP_CAP - earnedToday));
  if (award === 0) return {award: 0, update: null};

  const xp = current.xp + award;
  return {
    award: award,
    update: {
      xp: xp,
      level: levelForXp(xp),
      totalXp: current.totalXp + award,
      todayXp: earnedToday + award,
      xpDay: day.key,
      xpDayEndsAt: day.endsAt,
    },
  };
}

/**
 * Moves a level-100 player back to level 1 with one more prestige. XP beyond
 * level 100 carries over, so waiting to prestige never costs anything.
 *
 * @param {object|null} profile Stored profile.
 * @return {object} The profile fields to write.
 */
function applyPrestige(profile) {
  const current = progressOf(profile);
  const needed = xpForLevel(MAX_LEVEL);
  if (current.xp < needed) {
    throw new Error(`Reach level ${MAX_LEVEL} before you prestige.`);
  }
  const xp = current.xp - needed;
  return {xp: xp, level: levelForXp(xp), prestige: current.prestige + 1};
}

// --- Usernames ---------------------------------------------------------------

const ADJECTIVES = new Set(words.adjectives);
const CREATURES = new Set(words.creatures);
const BLOCKED_INITIALS = new Set(words.blockedInitials);

/**
 * @param {string} adjective From the adjective list.
 * @param {string} creature From the creature list.
 * @return {string} Two capital letters for the avatar.
 */
function initialsOf(adjective, creature) {
  return `${adjective[0]}${creature[0]}`.toUpperCase();
}

/**
 * Checks a requested username against the word lists. Anything not built
 * exactly from them is refused, which is what makes an inappropriate name
 * impossible rather than merely unlikely.
 *
 * @param {*} adjective Requested adjective.
 * @param {*} creature Requested creature.
 * @return {{adjective: string, creature: string, displayName: string,
 *     initials: string, key: string}} The accepted name.
 */
function validateUsername(adjective, creature) {
  if (!ADJECTIVES.has(adjective) || !CREATURES.has(creature)) {
    throw new Error("Pick a name from the lists.");
  }
  const initials = initialsOf(adjective, creature);
  if (BLOCKED_INITIALS.has(initials)) {
    throw new Error("That pair is not available. Try another.");
  }
  return {
    adjective: adjective,
    creature: creature,
    displayName: `${adjective} ${creature}`,
    initials: initials,
    key: `${adjective}-${creature}`.toLowerCase(),
  };
}

/**
 * A random allowed username, for new players and the shuffle button.
 *
 * @param {function(): number} [random] Source of numbers in [0, 1).
 * @return {object} Same shape as validateUsername.
 */
function randomUsername(random = Math.random) {
  for (;;) {
    const adjective =
      words.adjectives[Math.floor(random() * words.adjectives.length)];
    const creature =
      words.creatures[Math.floor(random() * words.creatures.length)];
    if (!BLOCKED_INITIALS.has(initialsOf(adjective, creature))) {
      return validateUsername(adjective, creature);
    }
  }
}

module.exports = {
  MAX_LEVEL,
  DAILY_XP_CAP,
  BASE_TASK_XP,
  MAX_TASK_XP,
  xpForLevel,
  levelForXp,
  taskXp,
  xpDay,
  progressOf,
  applyAward,
  applyPrestige,
  initialsOf,
  validateUsername,
  randomUsername,
  words,
};
