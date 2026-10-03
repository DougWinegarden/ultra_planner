const test = require("node:test");
const assert = require("node:assert");
const {
  MAX_LEVEL,
  DAILY_XP_CAP,
  BASE_TASK_XP,
  MAX_TASK_XP,
  xpForLevel,
  levelForXp,
  taskXp,
  xpDay,
  applyAward,
  applyPrestige,
  validateUsername,
  randomUsername,
  initialsOf,
  words,
} = require("../progress");

// --- The level curve ---------------------------------------------------------

test("the curve matches the RuneScape table", () => {
  assert.equal(xpForLevel(1), 0);
  assert.equal(xpForLevel(2), 83);
  assert.equal(xpForLevel(50), 101333);
  assert.equal(xpForLevel(92), 6517253);
  assert.equal(xpForLevel(99), 13034431);
  assert.equal(xpForLevel(100), 14391160);
});

test("level 92 is half of level 99", () => {
  assert.ok(Math.abs(xpForLevel(92) / xpForLevel(99) - 0.5) < 0.001);
});

test("every level costs more than the one before", () => {
  for (let level = 3; level <= MAX_LEVEL; level++) {
    const step = xpForLevel(level) - xpForLevel(level - 1);
    const previous = xpForLevel(level - 1) - xpForLevel(level - 2);
    assert.ok(step > previous, `level ${level} is no harder than the last`);
  }
});

test("levels change exactly at their thresholds", () => {
  assert.equal(levelForXp(0), 1);
  assert.equal(levelForXp(82), 1);
  assert.equal(levelForXp(83), 2);
  assert.equal(levelForXp(xpForLevel(57) - 1), 56);
  assert.equal(levelForXp(xpForLevel(57)), 57);
});

test("XP past level 100 keeps the level at 100", () => {
  assert.equal(levelForXp(xpForLevel(100) * 3), 100);
});

test("earning the cap daily reaches level 100 in about three months", () => {
  const days = Math.ceil(xpForLevel(100) / DAILY_XP_CAP);
  assert.ok(days >= 88 && days <= 92, `took ${days} days`);
});

// --- Task values -------------------------------------------------------------

test("tasks are worth more the longer they take, up to a limit", () => {
  assert.equal(taskXp(null), BASE_TASK_XP);
  assert.equal(taskXp(undefined), BASE_TASK_XP);
  assert.equal(taskXp(15), BASE_TASK_XP);
  assert.equal(taskXp(30), BASE_TASK_XP);
  assert.equal(taskXp(45), 25000);
  assert.equal(taskXp(60), 25000);
  assert.equal(taskXp(120), 35000);
  assert.equal(taskXp(600), MAX_TASK_XP);
});

test("a junk duration is worth the base", () => {
  assert.equal(taskXp(NaN), BASE_TASK_XP);
  assert.equal(taskXp("999"), BASE_TASK_XP);
  assert.equal(taskXp(-60), BASE_TASK_XP);
});

// --- The XP day --------------------------------------------------------------

const LA = "America/Los_Angeles";

test("the XP day follows the configured zone, not UTC", () => {
  // 2026-10-03 05:00 UTC is still 2 October, 22:00 in Los Angeles.
  const day = xpDay(Date.UTC(2026, 9, 3, 5, 0), LA);
  assert.equal(day.key, "2026-10-02");
  // Midnight PDT is 07:00 UTC.
  assert.equal(day.endsAt, Date.UTC(2026, 9, 3, 7, 0));
});

test("the day that clocks go back ends at the right midnight", () => {
  // 1 November 2026 has 25 hours in Los Angeles; it ends at midnight PST.
  const day = xpDay(Date.UTC(2026, 10, 1, 12, 0), LA);
  assert.equal(day.key, "2026-11-01");
  assert.equal(day.endsAt, Date.UTC(2026, 10, 2, 8, 0));
});

test("the day that clocks go forward ends at the right midnight", () => {
  const day = xpDay(Date.UTC(2026, 2, 8, 12, 0), LA);
  assert.equal(day.key, "2026-03-08");
  assert.equal(day.endsAt, Date.UTC(2026, 2, 9, 7, 0));
});

// --- Awards ------------------------------------------------------------------

const TODAY = {key: "2026-10-02", endsAt: 1};
const TOMORROW = {key: "2026-10-03", endsAt: 2};

test("a first award starts a profile from nothing", () => {
  const {award, update} = applyAward(null, 20000, TODAY);
  assert.equal(award, 20000);
  assert.deepEqual(update, {
    xp: 20000,
    level: levelForXp(20000),
    totalXp: 20000,
    todayXp: 20000,
    xpDay: "2026-10-02",
    xpDayEndsAt: 1,
  });
});

test("the daily cap trims the last award and blocks the rest", () => {
  const nearlyCapped = {
    xp: 500000,
    totalXp: 500000,
    todayXp: DAILY_XP_CAP - 5000,
    xpDay: TODAY.key,
  };

  const trimmed = applyAward(nearlyCapped, 20000, TODAY);
  assert.equal(trimmed.award, 5000);
  assert.equal(trimmed.update.todayXp, DAILY_XP_CAP);

  const blocked = applyAward(
    {...nearlyCapped, todayXp: DAILY_XP_CAP},
    20000,
    TODAY,
  );
  assert.deepEqual(blocked, {award: 0, update: null});
});

test("the cap resets on a new day", () => {
  const cappedYesterday = {
    xp: 500000,
    totalXp: 500000,
    todayXp: DAILY_XP_CAP,
    xpDay: TODAY.key,
  };
  const {award, update} = applyAward(cappedYesterday, 20000, TOMORROW);
  assert.equal(award, 20000);
  assert.equal(update.todayXp, 20000);
});

test("farming many tasks in a day cannot beat the cap", () => {
  let profile = null;
  let earned = 0;
  for (let i = 0; i < 500; i++) {
    const {award, update} = applyAward(profile, MAX_TASK_XP, TODAY);
    earned += award;
    if (update) profile = {...profile, ...update};
  }
  assert.equal(earned, DAILY_XP_CAP);
});

test("XP keeps building past level 100", () => {
  const atMax = {
    xp: xpForLevel(100),
    totalXp: xpForLevel(100),
    todayXp: 0,
    xpDay: TODAY.key,
  };
  const {update} = applyAward(atMax, 20000, TODAY);
  assert.equal(update.xp, xpForLevel(100) + 20000);
  assert.equal(update.level, 100);
});

// --- Prestige ----------------------------------------------------------------

test("prestige needs level 100", () => {
  assert.throws(
    () => applyPrestige({xp: xpForLevel(100) - 1}),
    /level 100/,
  );
});

test("prestige keeps XP earned beyond level 100", () => {
  const update = applyPrestige({xp: xpForLevel(100) + 150000, prestige: 2});
  assert.equal(update.prestige, 3);
  assert.equal(update.xp, 150000);
  assert.equal(update.level, levelForXp(150000));
});

test("prestige at exactly level 100 starts again from level 1", () => {
  const update = applyPrestige({xp: xpForLevel(100)});
  assert.deepEqual(update, {xp: 0, level: 1, prestige: 1});
});

// --- Usernames ---------------------------------------------------------------

test("a name is built from one adjective and one creature", () => {
  assert.deepEqual(validateUsername("Brave", "Otter"), {
    adjective: "Brave",
    creature: "Otter",
    displayName: "Brave Otter",
    initials: "BO",
    key: "brave-otter",
  });
});

test("anything not exactly from the lists is refused", () => {
  for (const [adjective, creature] of [
    ["brave", "Otter"],
    ["Brave ", "Otter"],
    ["Brave", "Otters"],
    ["Brave", ""],
    ["Brave", "Otter Otter"],
    ["Brave", {toString: () => "Otter"}],
    [null, "Otter"],
    ["B r a v e", "Otter"],
  ]) {
    assert.throws(() => validateUsername(adjective, creature), /lists/);
  }
});

test("pairs with blocked initials are refused", () => {
  assert.throws(() => validateUsername("Swift", "Seal"), /not available/);
  assert.throws(() => validateUsername("Fearless", "Urchin"), /not available/);
});

test("random names are always allowed", () => {
  let seed = 1;
  const random = () => {
    seed = (seed * 16807) % 2147483647;
    return (seed - 1) / 2147483646;
  };
  for (let i = 0; i < 2000; i++) {
    const name = randomUsername(random);
    assert.doesNotThrow(() => validateUsername(name.adjective, name.creature));
  }
});

test("every word is a single plain capitalised word", () => {
  for (const word of [...words.adjectives, ...words.creatures]) {
    assert.match(word, /^[A-Z][a-z]+$/, word);
  }
});

test("the lists have no duplicates", () => {
  assert.equal(new Set(words.adjectives).size, words.adjectives.length);
  assert.equal(new Set(words.creatures).size, words.creatures.length);
});

test("there are plenty of names to go round", () => {
  let allowed = 0;
  for (const adjective of words.adjectives) {
    for (const creature of words.creatures) {
      if (!words.blockedInitials.includes(initialsOf(adjective, creature))) {
        allowed++;
      }
    }
  }
  assert.ok(allowed > 2000, `only ${allowed} names`);
});
