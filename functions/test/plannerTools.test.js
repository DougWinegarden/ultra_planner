const test = require("node:test");
const assert = require("node:assert");
const {
  MAX_CHANGES,
  PlannerSession,
  TOOL_DECLARATIONS,
  parseSnapshot,
  plannerInstructions,
  addDays,
  weekdayOf,
} = require("../plannerTools");

// Friday 2 October 2026, 14:05.
const NOW = "2026-10-02T14:05";

/**
 * Builds a session from a compact task list.
 *
 * @param {Array<object>} tasks Tasks to put in the snapshot.
 * @param {object} [extra] Snapshot overrides.
 * @return {PlannerSession} A fresh session.
 */
function session(tasks, extra = {}) {
  return new PlannerSession(parseSnapshot({
    now: NOW,
    defaultListId: "school",
    lists: [
      {id: "school", name: "School"},
      {id: "home", name: "Home"},
    ],
    tasks: tasks,
    ...extra,
  }));
}

/**
 * @param {string} id Task id.
 * @param {object} fields Anything beyond the defaults.
 * @return {object} A task as the app sends it.
 */
function task(id, fields) {
  return {
    id: id,
    name: id,
    listId: "school",
    date: null,
    time: null,
    durationMinutes: null,
    done: false,
    ...fields,
  };
}

// --- Calendar arithmetic -----------------------------------------------------

test("dates add across month and year ends", () => {
  assert.equal(addDays("2026-10-31", 1), "2026-11-01");
  assert.equal(addDays("2026-12-31", 1), "2027-01-01");
  assert.equal(addDays("2028-03-01", -1), "2028-02-29");
});

test("weekday names match the calendar", () => {
  assert.equal(weekdayOf("2026-10-02"), "Friday");
  assert.equal(weekdayOf("2026-10-04"), "Sunday");
});

// --- Snapshot ----------------------------------------------------------------

test("a snapshot without a valid current time is rejected", () => {
  assert.throws(() => parseSnapshot({now: "tomorrow", lists: [], tasks: []}));
  assert.throws(() => parseSnapshot(null));
});

test("malformed task fields are dropped, not fatal", () => {
  const parsed = parseSnapshot({
    now: NOW,
    lists: [],
    tasks: [
      {id: "a", name: "A", date: "2026-02-30", time: "17:00"},
      {id: "b", name: "B", date: "2026-10-03", time: "25:00"},
      {id: "c", name: "C", date: "2026-10-03", durationMinutes: 99999},
      {name: "no id"},
    ],
  });

  assert.equal(parsed.tasks.size, 3);
  // An impossible date takes its time with it: a time needs a day.
  assert.equal(parsed.tasks.get("a").date, null);
  assert.equal(parsed.tasks.get("a").time, null);
  assert.equal(parsed.tasks.get("b").time, null);
  assert.equal(parsed.tasks.get("c").durationMinutes, null);
});

test("the default list falls back to the first list", () => {
  const parsed = parseSnapshot({
    now: NOW,
    defaultListId: "gone",
    lists: [{id: "x", name: "X"}],
    tasks: [],
  });
  assert.equal(parsed.defaultListId, "x");
});

test("instructions carry today's date, weekday and the lists", () => {
  const text = plannerInstructions(session([]).snapshot);
  assert.match(text, /Friday, 2026-10-02/);
  assert.match(text, /14:05/);
  assert.match(text, /"School" \(id: school\)/);
});

test("every tool declaration names its required arguments", () => {
  for (const declaration of TOOL_DECLARATIONS) {
    const props = declaration.parameters.properties;
    for (const name of declaration.parameters.required || []) {
      assert.ok(props[name], `${declaration.name}.${name} is not declared`);
    }
  }
});

// --- get_tasks ---------------------------------------------------------------

test("get_tasks filters to a date range and sorts by time", () => {
  const s = session([
    task("late", {date: "2026-10-03", time: "19:00"}),
    task("early", {date: "2026-10-03", time: "08:30"}),
    task("allday", {date: "2026-10-03"}),
    task("other day", {date: "2026-10-04"}),
    task("undated", {}),
  ]);

  const result = s.execute("get_tasks", {start_date: "2026-10-03"});

  assert.deepEqual(result.tasks.map((t) => t.id), ["early", "late", "allday"]);
  assert.equal(result.tasks[0].weekday, "Saturday");
});

test("get_tasks finds overdue work only", () => {
  const s = session([
    task("late", {date: "2026-10-01"}),
    task("late but done", {date: "2026-10-01", done: true}),
    task("today", {date: "2026-10-02"}),
  ]);

  const result = s.execute("get_tasks", {status: "overdue"});

  assert.deepEqual(result.tasks.map((t) => t.id), ["late"]);
  assert.equal(result.tasks[0].overdue, true);
});

test("get_tasks hides done tasks unless asked", () => {
  const s = session([task("done", {done: true}), task("open", {})]);

  assert.deepEqual(
    s.execute("get_tasks", {}).tasks.map((t) => t.id),
    ["open"],
  );
  assert.equal(s.execute("get_tasks", {status: "all"}).count, 2);
});

test("get_tasks matches names without regard to case", () => {
  const s = session([task("Math homework", {}), task("Read", {})]);
  const result = s.execute("get_tasks", {query: "MATH"});
  assert.deepEqual(result.tasks.map((t) => t.id), ["Math homework"]);
});

test("get_tasks reports overlapping timed tasks as conflicts", () => {
  const s = session([
    task("math", {date: "2026-10-03", time: "16:00", durationMinutes: 60}),
    task("soccer", {date: "2026-10-03", time: "16:30", durationMinutes: 90}),
    task("dinner", {date: "2026-10-03", time: "18:30", durationMinutes: 30}),
  ]);

  const result = s.execute("get_tasks", {start_date: "2026-10-03"});

  assert.deepEqual(result.conflicts, [{
    date: "2026-10-03",
    task_ids: ["math", "soccer"],
    names: ["math", "soccer"],
  }]);
});

test("get_tasks rejects a backwards range", () => {
  const s = session([]);
  const result = s.execute("get_tasks", {
    start_date: "2026-10-05",
    end_date: "2026-10-01",
  });
  assert.match(result.error, /before/);
});

// --- find_free_time ----------------------------------------------------------

test("free time is the gaps between timed tasks", () => {
  const s = session([
    task("school", {date: "2026-10-05", time: "08:00", durationMinutes: 420}),
    task("soccer", {date: "2026-10-05", time: "16:30", durationMinutes: 90}),
  ]);

  const result = s.execute("find_free_time", {
    duration_minutes: 60,
    start_date: "2026-10-05",
  });

  assert.deepEqual(result.free, [
    {date: "2026-10-05", weekday: "Monday", start: "15:00", end: "16:30",
      minutes: 90},
    {date: "2026-10-05", weekday: "Monday", start: "18:00", end: "21:00",
      minutes: 180},
  ]);
});

test("free time today starts after now, not at the start of the day", () => {
  const s = session([]);
  const result = s.execute("find_free_time", {
    duration_minutes: 30,
    start_date: "2026-10-02",
  });
  // 14:05 rounds up to the next quarter hour.
  assert.equal(result.free[0].start, "14:15");
});

test("free time never offers days that have already passed", () => {
  const s = session([]);
  const result = s.execute("find_free_time", {
    duration_minutes: 30,
    start_date: "2026-09-28",
    end_date: "2026-10-03",
  });
  assert.deepEqual(
    result.free.map((w) => w.date),
    ["2026-10-02", "2026-10-03"],
  );
});

test("a timed task without a duration still blocks some time", () => {
  const s = session([task("call", {date: "2026-10-05", time: "08:00"})]);
  const result = s.execute("find_free_time", {
    duration_minutes: 30,
    start_date: "2026-10-05",
  });
  assert.equal(result.free[0].start, "08:30");
});

test("windows too short for the request are left out", () => {
  const s = session([
    // 08:30 for twelve hours leaves 30 minutes either side.
    task("a", {date: "2026-10-05", time: "08:30", durationMinutes: 720}),
  ]);
  const result = s.execute("find_free_time", {
    duration_minutes: 60,
    start_date: "2026-10-05",
  });
  assert.deepEqual(result.free, []);
  assert.match(result.note, /No free window/);
});

test("find_free_time checks its arguments", () => {
  const s = session([]);
  assert.ok(s.execute("find_free_time", {start_date: "2026-10-05"}).error);
  assert.ok(s.execute("find_free_time", {
    duration_minutes: 30,
    start_date: "2026-10-05",
    end_date: "2026-12-30",
  }).error);
  assert.ok(s.execute("find_free_time", {
    duration_minutes: 30,
    start_date: "2026-10-05",
    day_start: "20:00",
    day_end: "09:00",
  }).error);
});

// --- Write tools and the resulting changes -----------------------------------

test("creating a task proposes it in the default list", () => {
  const s = session([]);
  const result = s.execute("create_task", {
    name: "Game project",
    date: "2026-10-03",
    time: "14:00",
    duration_minutes: 120,
  });

  assert.equal(result.ok, true);
  assert.equal(result.task.end, "16:00");
  assert.deepEqual(s.changes(), [{
    type: "create",
    after: {
      name: "Game project",
      listId: "school",
      listName: "School",
      date: "2026-10-03",
      time: "14:00",
      durationMinutes: 120,
      done: false,
    },
  }]);
});

test("moving a task keeps its time and records before and after", () => {
  const s = session([task("math", {date: "2026-10-02", time: "17:00"})]);

  s.execute("update_task", {task_id: "math", date: "2026-10-03"});

  const [change] = s.changes();
  assert.equal(change.type, "update");
  assert.equal(change.taskId, "math");
  assert.equal(change.before.date, "2026-10-02");
  assert.equal(change.after.date, "2026-10-03");
  assert.equal(change.after.time, "17:00");
});

test("a write is visible to later reads in the same turn", () => {
  const s = session([]);
  s.execute("create_task", {
    name: "Gym",
    date: "2026-10-05",
    time: "15:00",
    duration_minutes: 60,
  });

  const free = s.execute("find_free_time", {
    duration_minutes: 60,
    start_date: "2026-10-05",
  });

  assert.deepEqual(
    free.free.map((w) => `${w.start}-${w.end}`),
    ["08:00-15:00", "16:00-21:00"],
  );
});

test("an update to a proposed task folds into its create", () => {
  const s = session([]);
  const {task: created} = s.execute("create_task", {name: "Run"});
  s.execute("update_task", {task_id: created.id, date: "2026-10-06"});

  const changes = s.changes();
  assert.equal(changes.length, 1);
  assert.equal(changes[0].type, "create");
  assert.equal(changes[0].after.date, "2026-10-06");
});

test("creating then deleting a task proposes nothing", () => {
  const s = session([]);
  const {task: created} = s.execute("create_task", {name: "Oops"});
  s.execute("delete_task", {task_id: created.id});
  assert.deepEqual(s.changes(), []);
});

test("an update reverted in the same turn proposes nothing", () => {
  const s = session([task("essay", {date: "2026-10-03"})]);
  s.execute("update_task", {task_id: "essay", date: "2026-10-04"});
  s.execute("update_task", {task_id: "essay", date: "2026-10-03"});
  assert.deepEqual(s.changes(), []);
});

test("updating then deleting proposes a delete of the original", () => {
  const s = session([task("essay", {date: "2026-10-03"})]);
  s.execute("update_task", {task_id: "essay", name: "Renamed"});
  s.execute("delete_task", {task_id: "essay"});

  assert.deepEqual(s.changes(), [{
    type: "delete",
    taskId: "essay",
    before: {
      name: "essay",
      listId: "school",
      listName: "School",
      date: "2026-10-03",
      time: null,
      durationMinutes: null,
      done: false,
    },
  }]);
});

test("a deleted task cannot be changed again", () => {
  const s = session([task("essay", {})]);
  s.execute("delete_task", {task_id: "essay"});
  assert.match(s.execute("update_task", {task_id: "essay", done: true}).error,
    /no task/);
});

test("removing the date also removes the time", () => {
  const s = session([task("a", {date: "2026-10-03", time: "09:00"})]);
  s.execute("update_task", {task_id: "a", remove_date: true});
  const [change] = s.changes();
  assert.equal(change.after.date, null);
  assert.equal(change.after.time, null);
});

test("write tools refuse what the app could not save", () => {
  const s = session([task("a", {})]);

  assert.match(s.execute("update_task", {task_id: "nope", done: true}).error,
    /no task/);
  assert.match(s.execute("update_task", {task_id: "a", time: "09:00"}).error,
    /needs a date/);
  assert.match(s.execute("update_task", {task_id: "a"}).error, /Nothing/);
  assert.match(s.execute("update_task", {task_id: "a", list_id: "x"}).error,
    /no list/);
  assert.match(s.execute("create_task", {name: "  "}).error, /name/);
  assert.match(s.execute("create_task", {name: "x", time: "09:00"}).error,
    /needs a date/);
  assert.match(
    s.execute("create_task", {name: "x", duration_minutes: 2}).error,
    /duration/,
  );
  assert.match(s.execute("nonsense", {}).error, /no tool/);
  assert.deepEqual(s.changes(), []);
});

test("null arguments count as left out", () => {
  const s = session([task("a", {date: "2026-10-03"})]);
  const result = s.execute("update_task", {
    task_id: "a",
    done: true,
    date: null,
    time: null,
    name: null,
  });
  assert.equal(result.ok, true);
  assert.equal(s.changes()[0].after.date, "2026-10-03");
});

test("a turn cannot change more than the change budget", () => {
  const s = session([]);
  for (let i = 0; i < MAX_CHANGES; i++) {
    assert.equal(s.execute("create_task", {name: `t${i}`}).ok, true);
  }
  assert.match(s.execute("create_task", {name: "one too many"}).error,
    /more than/);
  assert.equal(s.changes().length, MAX_CHANGES);
});

test("creating a task with no lists explains why it cannot", () => {
  const s = session([], {lists: [], defaultListId: null});
  assert.match(s.execute("create_task", {name: "x"}).error, /no lists/);
});
