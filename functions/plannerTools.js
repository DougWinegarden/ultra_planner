/**
 * The planner tools Quackers can call, and the working copy they act on.
 *
 * The app sends a snapshot of the user's lists and tasks with each question.
 * Read tools answer from that snapshot. Write tools change a working copy of
 * it and never touch Firestore: when the turn ends, the difference between the
 * snapshot and the working copy goes back to the app as proposed changes, which
 * the user approves and the app writes with its own Firestore access. Security
 * rules therefore still decide what is allowed, and a bad model decision costs
 * the user one tap on Cancel rather than their calendar.
 *
 * Everything is in the user's local wall-clock time -- dates are "YYYY-MM-DD",
 * times are 24-hour "HH:MM", exactly as the app sent them. The server never
 * converts time zones, so it cannot get one wrong.
 *
 * Pure: no Firestore and no network, so every tool is unit tested directly.
 */

/** Snapshot size limits; a real account is far below these. */
const MAX_TASKS = 3000;
const MAX_LISTS = 200;
const MAX_NAME_CHARS = 200;

/** Most tasks one turn may change, so a runaway plan stays reviewable. */
const MAX_CHANGES = 40;

/** Most tasks get_tasks returns; the model is told when more matched. */
const MAX_RESULTS = 100;

/** Most windows find_free_time returns. */
const MAX_FREE_WINDOWS = 30;

/** Longest date range find_free_time searches. */
const MAX_RANGE_DAYS = 31;

const MIN_DURATION_MINUTES = 5;
const MAX_DURATION_MINUTES = 12 * 60;

/** How long a timed task with no duration is treated as taking. */
const DEFAULT_BLOCK_MINUTES = 30;

const DEFAULT_DAY_START = "08:00";
const DEFAULT_DAY_END = "21:00";

/** Free windows today start no earlier than now, rounded up to this step. */
const NOW_ROUNDING_MINUTES = 15;

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;
const DAY_MS = 24 * 60 * 60 * 1000;
const WEEKDAYS = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];

/** A mistake the model can fix; its message is sent back to the model. */
class ToolError extends Error {}

// --- Calendar arithmetic -----------------------------------------------------
//
// Dates are handled as day numbers in UTC purely as a counting device: no date
// here is ever an instant, so no time zone is involved.

/**
 * @param {*} value Candidate date.
 * @return {boolean} Whether it is a real calendar date as YYYY-MM-DD.
 */
function isValidDate(value) {
  if (typeof value !== "string" || !DATE_PATTERN.test(value)) return false;
  const [y, m, d] = value.split("-").map(Number);
  if (y < 1970 || y > 2200) return false;
  const probe = new Date(Date.UTC(y, m - 1, d));
  return probe.getUTCMonth() === m - 1 && probe.getUTCDate() === d;
}

/**
 * @param {*} value Candidate time.
 * @return {boolean} Whether it is a 24-hour HH:MM time.
 */
function isValidTime(value) {
  return typeof value === "string" && TIME_PATTERN.test(value);
}

/**
 * @param {string} date YYYY-MM-DD.
 * @return {number} Days since 1970-01-01.
 */
function dayNumber(date) {
  const [y, m, d] = date.split("-").map(Number);
  return Math.round(Date.UTC(y, m - 1, d) / DAY_MS);
}

/**
 * @param {string} date YYYY-MM-DD.
 * @param {number} days Days to add; may be negative.
 * @return {string} The resulting YYYY-MM-DD.
 */
function addDays(date, days) {
  return new Date((dayNumber(date) + days) * DAY_MS).toISOString().slice(0, 10);
}

/**
 * @param {string} date YYYY-MM-DD.
 * @return {string} English weekday name.
 */
function weekdayOf(date) {
  return WEEKDAYS[new Date(dayNumber(date) * DAY_MS).getUTCDay()];
}

/**
 * @param {string} time HH:MM.
 * @return {number} Minutes after midnight.
 */
function toMinutes(time) {
  const [h, m] = time.split(":").map(Number);
  return h * 60 + m;
}

/**
 * @param {number} minutes Minutes after midnight; clamped to 24:00.
 * @return {string} HH:MM.
 */
function fromMinutes(minutes) {
  const clamped = Math.max(0, Math.min(24 * 60, minutes));
  const h = String(Math.floor(clamped / 60)).padStart(2, "0");
  const m = String(clamped % 60).padStart(2, "0");
  return `${h}:${m}`;
}

// --- Snapshot ----------------------------------------------------------------

/**
 * @param {*} value Candidate name.
 * @return {string} Trimmed, length-capped name; empty when unusable.
 */
function cleanName(value) {
  return typeof value === "string" ?
    value.trim().slice(0, MAX_NAME_CHARS) :
    "";
}

/**
 * @param {*} value Candidate duration.
 * @return {boolean} Whether it is a whole number of minutes in range.
 */
function isValidDuration(value) {
  return Number.isInteger(value) &&
    value >= MIN_DURATION_MINUTES &&
    value <= MAX_DURATION_MINUTES;
}

/**
 * Normalizes one task from the app, dropping any field that is malformed
 * rather than rejecting the whole snapshot over it.
 *
 * @param {object} raw Task as the app sent it.
 * @return {object} {name, listId, date, time, durationMinutes, done}.
 */
function parseTaskState(raw) {
  const date = isValidDate(raw.date) ? raw.date : null;
  return {
    name: cleanName(raw.name) || "Untitled task",
    listId: typeof raw.listId === "string" ? raw.listId : "",
    date: date,
    // A time of day means nothing without a day to put it on.
    time: date !== null && isValidTime(raw.time) ? raw.time : null,
    durationMinutes: isValidDuration(raw.durationMinutes) ?
      raw.durationMinutes :
      null,
    done: raw.done === true,
  };
}

/**
 * Validates the snapshot the app sent with the question.
 *
 * @param {object} raw {now: "YYYY-MM-DDTHH:MM", defaultListId,
 *     lists: [{id, name}], tasks: [{id, name, listId, date, time,
 *     durationMinutes, done}]}.
 * @return {object} {today, nowTime, lists, tasks: Map, defaultListId}.
 */
function parseSnapshot(raw) {
  if (!raw || typeof raw !== "object") {
    throw new Error("The planner snapshot is missing.");
  }

  const [today, nowTime] = typeof raw.now === "string" ?
    raw.now.split("T") :
    [];
  if (!isValidDate(today) || !isValidTime(nowTime)) {
    throw new Error("The planner snapshot has no valid current time.");
  }

  const rawLists = Array.isArray(raw.lists) ? raw.lists : [];
  const rawTasks = Array.isArray(raw.tasks) ? raw.tasks : [];
  if (rawLists.length > MAX_LISTS || rawTasks.length > MAX_TASKS) {
    throw new Error("There are too many tasks to plan with at once.");
  }

  const lists = rawLists
    .filter((l) => l && typeof l.id === "string" && l.id !== "")
    .map((l) => ({id: l.id, name: cleanName(l.name) || "Untitled list"}));

  const tasks = new Map();
  for (const t of rawTasks) {
    if (t && typeof t.id === "string" && t.id !== "") {
      tasks.set(t.id, parseTaskState(t));
    }
  }

  const listIds = new Set(lists.map((l) => l.id));
  const defaultListId = listIds.has(raw.defaultListId) ?
    raw.defaultListId :
    (lists.length > 0 ? lists[0].id : null);

  return {today, nowTime, lists, tasks, defaultListId};
}

// --- Tool declarations -------------------------------------------------------

const TOOL_DECLARATIONS = [
  {
    name: "get_tasks",
    description:
      "Looks up the user's tasks, sorted by date and time. Use it before " +
      "describing or changing any task, and to see what is planned on a " +
      "day. A task with a start time occupies the block from start to end. " +
      "Overlapping timed tasks on the same day are listed under conflicts.",
    parameters: {
      type: "object",
      properties: {
        start_date: {
          type: "string",
          description:
            "First date to include, YYYY-MM-DD. Leave out both dates to " +
            "search everything, including tasks with no date.",
        },
        end_date: {
          type: "string",
          description: "Last date to include, YYYY-MM-DD. Defaults to " +
            "start_date.",
        },
        status: {
          type: "string",
          enum: ["open", "done", "overdue", "all"],
          description:
            "open (default): not done yet. overdue: not done and due before " +
            "today. done: completed. all: everything.",
        },
        query: {
          type: "string",
          description: "Only tasks whose name contains this text.",
        },
        list_id: {
          type: "string",
          description: "Only tasks in this list.",
        },
      },
    },
  },
  {
    name: "find_free_time",
    description:
      "Finds open windows of at least duration_minutes between day_start " +
      "and day_end on each date in a range. Time taken by timed tasks and " +
      "time already past today are excluded. Use it before giving a task a " +
      "specific time.",
    parameters: {
      type: "object",
      properties: {
        duration_minutes: {
          type: "integer",
          description: "How long the free window must be, in minutes.",
        },
        start_date: {
          type: "string",
          description: "First date to search, YYYY-MM-DD.",
        },
        end_date: {
          type: "string",
          description:
            `Last date to search, YYYY-MM-DD. Defaults to start_date. At ` +
            `most ${MAX_RANGE_DAYS} days after start_date.`,
        },
        day_start: {
          type: "string",
          description: `Earliest start each day, HH:MM. Default ` +
            `${DEFAULT_DAY_START}.`,
        },
        day_end: {
          type: "string",
          description: `Latest end each day, HH:MM. Default ` +
            `${DEFAULT_DAY_END}.`,
        },
      },
      required: ["duration_minutes", "start_date"],
    },
  },
  {
    name: "create_task",
    description:
      "Proposes a new task. The user approves it in the app before it is " +
      "saved.",
    parameters: {
      type: "object",
      properties: {
        name: {type: "string", description: "What the task is."},
        list_id: {
          type: "string",
          description: "List to add it to. Defaults to the default list.",
        },
        date: {type: "string", description: "Due or scheduled date, " +
          "YYYY-MM-DD."},
        time: {
          type: "string",
          description: "Start time, HH:MM. Needs a date.",
        },
        duration_minutes: {
          type: "integer",
          description: `How long it takes, ${MIN_DURATION_MINUTES} to ` +
            `${MAX_DURATION_MINUTES} minutes.`,
        },
      },
      required: ["name"],
    },
  },
  {
    name: "update_task",
    description:
      "Proposes changes to an existing task: move it, rename it, change its " +
      "time or duration, move it to another list, or mark it done or not " +
      "done. Only the fields given change. The user approves it in the app " +
      "before it is saved.",
    parameters: {
      type: "object",
      properties: {
        task_id: {type: "string", description: "Id from get_tasks."},
        name: {type: "string", description: "New name."},
        date: {type: "string", description: "New date, YYYY-MM-DD. Keeps " +
          "the existing time unless time is also given."},
        time: {type: "string", description: "New start time, HH:MM."},
        duration_minutes: {
          type: "integer",
          description: `New length, ${MIN_DURATION_MINUTES} to ` +
            `${MAX_DURATION_MINUTES} minutes.`,
        },
        list_id: {type: "string", description: "Move it to this list."},
        done: {type: "boolean", description: "Mark done (true) or not " +
          "done (false)."},
        remove_date: {
          type: "boolean",
          description: "true removes the date and time entirely.",
        },
        remove_time: {
          type: "boolean",
          description: "true keeps the date but removes the time of day.",
        },
      },
      required: ["task_id"],
    },
  },
  {
    name: "delete_task",
    description:
      "Proposes deleting a task. Only use it when the user asked to delete " +
      "or remove something. The user approves it in the app first.",
    parameters: {
      type: "object",
      properties: {
        task_id: {type: "string", description: "Id from get_tasks."},
      },
      required: ["task_id"],
    },
  },
];

/**
 * Planner-specific instructions plus the facts the model cannot look up: the
 * current date and time, and the user's lists.
 *
 * @param {object} snapshot Parsed snapshot.
 * @return {string} Text for the system instruction.
 */
function plannerInstructions(snapshot) {
  const lists = snapshot.lists
    .map((l) => `${JSON.stringify(l.name)} (id: ${l.id})`)
    .join(", ");
  const fallback = snapshot.lists.find((l) => l.id === snapshot.defaultListId);

  return [
    "You can see and change the user's planner with your tools.",
    "- Look tasks up with get_tasks before describing or changing them, " +
      "and use the ids it returns. Never guess an id.",
    "- When the user asks for a change, make it with the tools instead of " +
      "telling them how to do it themselves.",
    "- Use find_free_time before giving a task a specific time, so it does " +
      "not overlap anything.",
    "- A task with a date but no time is due that day. A task with a time " +
      "occupies the block from its start for its duration.",
    "- Morning is 08:00-12:00, afternoon 12:00-17:00 and evening " +
      "17:00-21:00, unless the user says otherwise.",
    "- Only change what the user asked about. Never delete a task unless " +
      "the user asked to delete or remove it; to clear time, move tasks " +
      "instead.",
    "- If it is unclear which task or time the user means, ask one short " +
      "question instead of guessing.",
    "- Your changes are proposals that the user approves in the app. Say in " +
      "one or two short sentences what you set up, without claiming it is " +
      "already saved and without listing every change: the app shows them.",
    "",
    `Today is ${weekdayOf(snapshot.today)}, ${snapshot.today}, and the ` +
      `time is ${snapshot.nowTime}. All dates and times are the user's ` +
      "local time: dates are YYYY-MM-DD and times are 24-hour HH:MM.",
    lists === "" ?
      "The user has no lists yet, so new tasks cannot be created." :
      `The user's lists: ${lists}. New tasks go in ` +
        `${JSON.stringify(fallback.name)} unless another list fits better.`,
  ].join("\n");
}

// --- Session -----------------------------------------------------------------

/**
 * The working copy one turn's tools read and change.
 *
 * Changes are tracked by comparing the working copy against the original
 * snapshot, so a create followed by an update becomes one create, a create
 * followed by a delete disappears, and an update that is later undone in the
 * same turn proposes nothing.
 */
class PlannerSession {
  /**
   * @param {object} snapshot Result of parseSnapshot.
   */
  constructor(snapshot) {
    this.snapshot = snapshot;
    this.original = snapshot.tasks;
    /** Task id -> state, or null once deleted. */
    this.current = new Map(snapshot.tasks);
    /** Ids in the order they were first changed, which orders the result. */
    this.touched = [];
    this.nextNewId = 1;
    this.listsById = new Map(snapshot.lists.map((l) => [l.id, l]));
  }

  /**
   * Runs one tool call. Never throws: a problem comes back as {error} so the
   * model can read it and correct itself.
   *
   * @param {string} name Tool name.
   * @param {object} args Arguments from the model.
   * @return {object} The tool's response.
   */
  execute(name, args) {
    const safeArgs = args && typeof args === "object" ? args : {};
    try {
      switch (name) {
        case "get_tasks":
          return this.getTasks(safeArgs);
        case "find_free_time":
          return this.findFreeTime(safeArgs);
        case "create_task":
          return this.createTask(safeArgs);
        case "update_task":
          return this.updateTask(safeArgs);
        case "delete_task":
          return this.deleteTask(safeArgs);
        default:
          return {error: `There is no tool called ${name}.`};
      }
    } catch (error) {
      if (error instanceof ToolError) return {error: error.message};
      return {error: "That tool call failed. Check the arguments."};
    }
  }

  /**
   * The proposed changes, ready to send to the app.
   *
   * @return {Array<object>} {type: "create", after} | {type: "update", taskId,
   *     before, after} | {type: "delete", taskId, before}.
   */
  changes() {
    const result = [];
    for (const id of this.touched) {
      const before = this.original.get(id) || null;
      const after = this.current.get(id) || null;
      if (before === null && after !== null) {
        result.push({type: "create", after: this.wire(after)});
      } else if (before !== null && after === null) {
        result.push({type: "delete", taskId: id, before: this.wire(before)});
      } else if (before !== null && !sameState(before, after)) {
        result.push({
          type: "update",
          taskId: id,
          before: this.wire(before),
          after: this.wire(after),
        });
      }
    }
    return result;
  }

  // --- Read tools -----------------------------------------------------------

  /**
   * @param {object} args See TOOL_DECLARATIONS.
   * @return {object} {count, tasks, truncated, conflicts?}.
   */
  getTasks(args) {
    const status = given(args.status) ? args.status : "open";
    if (!["open", "done", "overdue", "all"].includes(status)) {
      throw new ToolError("status must be open, done, overdue or all.");
    }
    const startDate = optionalDate(args.start_date, "start_date");
    const endDate = optionalDate(args.end_date, "end_date") || startDate;
    if (startDate && endDate && endDate < startDate) {
      throw new ToolError("end_date is before start_date.");
    }
    const query = typeof args.query === "string" ?
      args.query.trim().toLowerCase() :
      "";
    const listId = given(args.list_id) ? this.requireList(args.list_id) : null;

    const matches = [];
    for (const [id, task] of this.current) {
      if (task === null) continue;
      if (status === "open" && task.done) continue;
      if (status === "done" && !task.done) continue;
      if (status === "overdue" && !this.isOverdue(task)) continue;
      if (startDate && (!task.date || task.date < startDate)) continue;
      if (endDate && (!task.date || task.date > endDate)) continue;
      if (query && !task.name.toLowerCase().includes(query)) continue;
      if (listId && task.listId !== listId) continue;
      matches.push([id, task]);
    }
    matches.sort(([, a], [, b]) => compareTasks(a, b));

    const shown = matches.slice(0, MAX_RESULTS);
    const result = {
      count: matches.length,
      tasks: shown.map(([id, task]) => this.view(id, task)),
      truncated: matches.length > shown.length,
    };
    const conflicts = findConflicts(shown);
    if (conflicts.length > 0) result.conflicts = conflicts;
    return result;
  }

  /**
   * @param {object} args See TOOL_DECLARATIONS.
   * @return {object} {free: [{date, weekday, start, end, minutes}], note?}.
   */
  findFreeTime(args) {
    const duration = requireDuration(args.duration_minutes);
    const startDate = requireDate(args.start_date, "start_date");
    const endDate = optionalDate(args.end_date, "end_date") || startDate;
    if (endDate < startDate) {
      throw new ToolError("end_date is before start_date.");
    }
    if (dayNumber(endDate) - dayNumber(startDate) > MAX_RANGE_DAYS) {
      throw new ToolError(
        `Search at most ${MAX_RANGE_DAYS} days at a time.`,
      );
    }
    const dayStart = toMinutes(
      optionalTime(args.day_start, "day_start") || DEFAULT_DAY_START,
    );
    const dayEnd = toMinutes(
      optionalTime(args.day_end, "day_end") || DEFAULT_DAY_END,
    );
    if (dayEnd <= dayStart) {
      throw new ToolError("day_end must be after day_start.");
    }

    const {today, nowTime} = this.snapshot;
    const free = [];
    let date = startDate < today ? today : startDate;

    while (date <= endDate && free.length < MAX_FREE_WINDOWS) {
      let cursor = dayStart;
      if (date === today) {
        const now = toMinutes(nowTime);
        const rounded =
          Math.ceil(now / NOW_ROUNDING_MINUTES) * NOW_ROUNDING_MINUTES;
        cursor = Math.max(cursor, rounded);
      }

      for (const [start, end] of this.busyBlocks(date)) {
        if (start - cursor >= duration) {
          free.push(this.window(date, cursor, Math.min(start, dayEnd)));
        }
        cursor = Math.max(cursor, end);
        if (cursor >= dayEnd) break;
      }
      if (dayEnd - cursor >= duration) {
        free.push(this.window(date, cursor, dayEnd));
      }
      date = addDays(date, 1);
    }

    // A window can be cut short by dayEnd above, so filter once more.
    const fitting = free
      .filter((w) => w.minutes >= duration)
      .slice(0, MAX_FREE_WINDOWS);
    if (fitting.length === 0) {
      return {
        free: [],
        note: `No free window of ${duration} minutes between ` +
          `${fromMinutes(dayStart)} and ${fromMinutes(dayEnd)} on those days.`,
      };
    }
    return {free: fitting};
  }

  // --- Write tools ----------------------------------------------------------

  /**
   * @param {object} args See TOOL_DECLARATIONS.
   * @return {object} {ok, task}.
   */
  createTask(args) {
    const name = cleanName(args.name);
    if (name === "") throw new ToolError("A task needs a name.");

    const listId = given(args.list_id) ?
      this.requireList(args.list_id) :
      this.snapshot.defaultListId;
    if (!listId) {
      throw new ToolError("The user has no lists, so a task cannot be added.");
    }

    const date = optionalDate(args.date, "date");
    const time = optionalTime(args.time, "time");
    if (time && !date) throw new ToolError("A time needs a date.");

    const state = {
      name: name,
      listId: listId,
      date: date,
      time: time,
      durationMinutes: given(args.duration_minutes) ?
        requireDuration(args.duration_minutes) :
        null,
      done: false,
    };

    const id = `new-${this.nextNewId++}`;
    this.record(id, state);
    return {ok: true, task: this.view(id, state)};
  }

  /**
   * @param {object} args See TOOL_DECLARATIONS.
   * @return {object} {ok, task}.
   */
  updateTask(args) {
    const id = args.task_id;
    const existing = this.requireTask(id);
    const next = {...existing};
    let changed = false;

    if (given(args.name)) {
      next.name = cleanName(args.name);
      if (next.name === "") throw new ToolError("A task needs a name.");
      changed = true;
    }
    if (given(args.list_id)) {
      next.listId = this.requireList(args.list_id);
      changed = true;
    }
    if (args.remove_date === true) {
      next.date = null;
      next.time = null;
      changed = true;
    }
    if (given(args.date)) {
      next.date = requireDate(args.date, "date");
      changed = true;
    }
    if (args.remove_time === true) {
      next.time = null;
      changed = true;
    }
    if (given(args.time)) {
      next.time = requireTime(args.time, "time");
      changed = true;
    }
    if (next.time && !next.date) {
      throw new ToolError("A time needs a date. Give a date as well.");
    }
    if (given(args.duration_minutes)) {
      next.durationMinutes = requireDuration(args.duration_minutes);
      changed = true;
    }
    if (given(args.done)) {
      if (typeof args.done !== "boolean") {
        throw new ToolError("done must be true or false.");
      }
      next.done = args.done;
      changed = true;
    }
    if (!changed) throw new ToolError("Nothing to change was given.");

    this.record(id, next);
    return {ok: true, task: this.view(id, next)};
  }

  /**
   * @param {object} args See TOOL_DECLARATIONS.
   * @return {object} {ok, deleted}.
   */
  deleteTask(args) {
    const id = args.task_id;
    const existing = this.requireTask(id);
    this.record(id, null);
    return {ok: true, deleted: this.view(id, existing)};
  }

  // --- Helpers --------------------------------------------------------------

  /**
   * Stores a new state for a task, enforcing the per-turn change budget.
   *
   * @param {string} id Task id.
   * @param {object|null} state New state, or null to delete.
   */
  record(id, state) {
    if (!this.touched.includes(id)) {
      if (this.touched.length >= MAX_CHANGES) {
        throw new ToolError(
          `That is more than ${MAX_CHANGES} changes at once. Do the most ` +
            "important ones and tell the user the rest can follow.",
        );
      }
      this.touched.push(id);
    }
    this.current.set(id, state);
  }

  /**
   * @param {*} id Task id from the model.
   * @return {object} The task's current state.
   */
  requireTask(id) {
    const task = typeof id === "string" ? this.current.get(id) : undefined;
    if (!task) {
      throw new ToolError(
        `There is no task with id ${JSON.stringify(id)}. Look it up with ` +
          "get_tasks.",
      );
    }
    return task;
  }

  /**
   * @param {*} id List id from the model.
   * @return {string} The id, once confirmed to exist.
   */
  requireList(id) {
    if (typeof id !== "string" || !this.listsById.has(id)) {
      throw new ToolError(`There is no list with id ${JSON.stringify(id)}.`);
    }
    return id;
  }

  /**
   * @param {object} task Task state.
   * @return {boolean} Not done and due before today.
   */
  isOverdue(task) {
    return !task.done && task.date !== null && task.date < this.snapshot.today;
  }

  /**
   * Merged busy intervals on one date, in minutes after midnight.
   *
   * Done tasks still count: a finished "Soccer 4:30-6:00" happened then.
   *
   * @param {string} date YYYY-MM-DD.
   * @return {Array<Array<number>>} Sorted, non-overlapping [start, end] pairs.
   */
  busyBlocks(date) {
    const blocks = [];
    for (const task of this.current.values()) {
      if (task && task.date === date && task.time) {
        const start = toMinutes(task.time);
        blocks.push([start, start + blockLength(task)]);
      }
    }
    blocks.sort((a, b) => a[0] - b[0]);

    const merged = [];
    for (const block of blocks) {
      const last = merged[merged.length - 1];
      if (last && block[0] <= last[1]) {
        last[1] = Math.max(last[1], block[1]);
      } else {
        merged.push(block);
      }
    }
    return merged;
  }

  /**
   * @param {string} date YYYY-MM-DD.
   * @param {number} start Minutes after midnight.
   * @param {number} end Minutes after midnight.
   * @return {object} A free window as the model sees it.
   */
  window(date, start, end) {
    return {
      date: date,
      weekday: weekdayOf(date),
      start: fromMinutes(start),
      end: fromMinutes(end),
      minutes: end - start,
    };
  }

  /**
   * How the model sees a task: compact, with derived fields precomputed so it
   * does not have to do date arithmetic.
   *
   * @param {string} id Task id.
   * @param {object} task Task state.
   * @return {object} View for a tool response.
   */
  view(id, task) {
    const list = this.listsById.get(task.listId);
    const view = {
      id: id,
      name: task.name,
      list: list ? list.name : "",
      done: task.done,
    };
    if (task.date) {
      view.date = task.date;
      view.weekday = weekdayOf(task.date);
    }
    if (task.time) {
      view.start = task.time;
      if (task.durationMinutes !== null) {
        view.end = fromMinutes(toMinutes(task.time) + task.durationMinutes);
      }
    }
    if (task.durationMinutes !== null) {
      view.duration_minutes = task.durationMinutes;
    }
    if (this.isOverdue(task)) view.overdue = true;
    return view;
  }

  /**
   * How the app receives a task state in a proposed change.
   *
   * @param {object} task Task state.
   * @return {object} Wire format, with the list name for display.
   */
  wire(task) {
    const list = this.listsById.get(task.listId);
    return {
      name: task.name,
      listId: task.listId,
      listName: list ? list.name : "",
      date: task.date,
      time: task.time,
      durationMinutes: task.durationMinutes,
      done: task.done,
    };
  }
}

/**
 * @param {object} task Task state.
 * @return {number} Minutes the task occupies on the calendar.
 */
function blockLength(task) {
  return task.durationMinutes === null ?
    DEFAULT_BLOCK_MINUTES :
    task.durationMinutes;
}

/**
 * Orders by date, then time, then name; undated and untimed sort last.
 *
 * @param {object} a Task state.
 * @param {object} b Task state.
 * @return {number} Comparator result.
 */
function compareTasks(a, b) {
  const dateA = a.date || "9999-99-99";
  const dateB = b.date || "9999-99-99";
  if (dateA !== dateB) return dateA < dateB ? -1 : 1;
  const timeA = a.time || "99:99";
  const timeB = b.time || "99:99";
  if (timeA !== timeB) return timeA < timeB ? -1 : 1;
  return a.name.localeCompare(b.name);
}

/**
 * Pairs of unfinished timed tasks that overlap on the same day.
 *
 * @param {Array<Array>} entries [id, task] pairs, sorted by compareTasks.
 * @return {Array<object>} {date, task_ids, names}, at most 20.
 */
function findConflicts(entries) {
  const timed = entries.filter(([, t]) => !t.done && t.date && t.time);
  const conflicts = [];
  for (let i = 0; i < timed.length && conflicts.length < 20; i++) {
    const [idA, a] = timed[i];
    const endA = toMinutes(a.time) + blockLength(a);
    for (let j = i + 1; j < timed.length; j++) {
      const [idB, b] = timed[j];
      // Sorted by date then start, so once B starts after A ends, so do the
      // rest of this day's tasks.
      if (b.date !== a.date || toMinutes(b.time) >= endA) break;
      conflicts.push({
        date: a.date,
        task_ids: [idA, idB],
        names: [a.name, b.name],
      });
    }
  }
  return conflicts;
}

/**
 * @param {object} a Task state.
 * @param {object} b Task state.
 * @return {boolean} Whether every field matches.
 */
function sameState(a, b) {
  return a.name === b.name &&
    a.listId === b.listId &&
    a.date === b.date &&
    a.time === b.time &&
    a.durationMinutes === b.durationMinutes &&
    a.done === b.done;
}

/**
 * Models sometimes send null for an optional argument they mean to leave out.
 *
 * @param {*} value Argument from the model.
 * @return {boolean} Whether it was actually given.
 */
function given(value) {
  return value !== undefined && value !== null;
}

/**
 * @param {*} value Candidate.
 * @param {string} field Argument name, for the error.
 * @return {string} The date.
 */
function requireDate(value, field) {
  if (!isValidDate(value)) {
    throw new ToolError(`${field} must be a real date as YYYY-MM-DD.`);
  }
  return value;
}

/**
 * @param {*} value Candidate; undefined, null and "" mean not given.
 * @param {string} field Argument name, for the error.
 * @return {string|null} The date, or null.
 */
function optionalDate(value, field) {
  if (value === undefined || value === null || value === "") return null;
  return requireDate(value, field);
}

/**
 * @param {*} value Candidate.
 * @param {string} field Argument name, for the error.
 * @return {string} The time.
 */
function requireTime(value, field) {
  if (!isValidTime(value)) {
    throw new ToolError(`${field} must be a 24-hour time as HH:MM.`);
  }
  return value;
}

/**
 * @param {*} value Candidate; undefined, null and "" mean not given.
 * @param {string} field Argument name, for the error.
 * @return {string|null} The time, or null.
 */
function optionalTime(value, field) {
  if (value === undefined || value === null || value === "") return null;
  return requireTime(value, field);
}

/**
 * @param {*} value Candidate; a float like 30.0 is accepted as 30.
 * @return {number} Whole minutes in range.
 */
function requireDuration(value) {
  const minutes = typeof value === "number" ? Math.round(value) : NaN;
  if (!isValidDuration(minutes)) {
    throw new ToolError(
      `duration_minutes must be ${MIN_DURATION_MINUTES} to ` +
        `${MAX_DURATION_MINUTES}.`,
    );
  }
  return minutes;
}

module.exports = {
  MAX_CHANGES,
  MAX_RESULTS,
  TOOL_DECLARATIONS,
  PlannerSession,
  parseSnapshot,
  plannerInstructions,
  addDays,
  weekdayOf,
};
