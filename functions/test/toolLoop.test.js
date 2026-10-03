const test = require("node:test");
const assert = require("node:assert");
const {runToolLoop, answerText} = require("../toolLoop");

/**
 * @param {Array<object>} parts Parts of the model's reply.
 * @return {object} A generateContent response body.
 */
function reply(parts) {
  return {candidates: [{content: {role: "model", parts: parts}}]};
}

/**
 * A fake model that returns the given bodies in order and records what it was
 * sent each time.
 *
 * @param {Array<object>} bodies Response bodies.
 * @return {{callModel: function, sent: Array}} The fake and its log.
 */
function scriptedModel(bodies) {
  const sent = [];
  return {
    sent: sent,
    callModel: async (contents) => {
      sent.push(JSON.parse(JSON.stringify(contents)));
      return bodies[sent.length - 1];
    },
  };
}

const QUESTION = [{role: "user", parts: [{text: "What's overdue?"}]}];

test("a plain answer ends the turn after one call", async () => {
  const model = scriptedModel([reply([{text: "All clear!"}])]);

  const turn = await runToolLoop({
    callModel: model.callModel,
    runTool: () => assert.fail("no tool should run"),
    contents: QUESTION,
  });

  assert.deepEqual(turn, {text: "All clear!", steps: 1, exhausted: false});
});

test("tool calls are run and their results sent back", async () => {
  const call = {
    functionCall: {name: "get_tasks", args: {status: "overdue"}, id: "c1"},
    thoughtSignature: "opaque-signature",
  };
  const model = scriptedModel([
    reply([call]),
    reply([{text: "Just your essay."}]),
  ]);
  const ran = [];

  const turn = await runToolLoop({
    callModel: model.callModel,
    runTool: (name, args) => {
      ran.push([name, args]);
      return {count: 1};
    },
    contents: QUESTION,
  });

  assert.equal(turn.text, "Just your essay.");
  assert.deepEqual(ran, [["get_tasks", {status: "overdue"}]]);

  const second = model.sent[1];
  // The model's call goes back verbatim, thought signature included.
  assert.deepEqual(second[1], {role: "model", parts: [call]});
  assert.deepEqual(second[2], {
    role: "user",
    parts: [{
      functionResponse: {name: "get_tasks", response: {count: 1}, id: "c1"},
    }],
  });
  // The caller's array is not modified.
  assert.equal(QUESTION.length, 1);
});

test("parallel calls get one response each, in order", async () => {
  const model = scriptedModel([
    reply([
      {functionCall: {name: "update_task", args: {task_id: "a"}}},
      {functionCall: {name: "update_task", args: {task_id: "b"}}},
    ]),
    reply([{text: "Moved both."}]),
  ]);

  await runToolLoop({
    callModel: model.callModel,
    runTool: (name, args) => ({ok: true, id: args.task_id}),
    contents: QUESTION,
  });

  const responses = model.sent[1][2].parts.map((p) => p.functionResponse);
  assert.deepEqual(responses.map((r) => r.response.id), ["a", "b"]);
  // No id was given, so none is invented.
  assert.equal("id" in responses[0], false);
});

test("the loop stops at the step cap", async () => {
  const looping = reply([{functionCall: {name: "get_tasks", args: {}}}]);
  const model = scriptedModel([looping, looping, looping]);

  const turn = await runToolLoop({
    callModel: model.callModel,
    runTool: () => ({count: 0}),
    contents: QUESTION,
    maxSteps: 3,
  });

  assert.deepEqual(turn, {text: "", steps: 3, exhausted: true});
  assert.equal(model.sent.length, 3);
});

test("a reply with no candidates ends the turn with no text", async () => {
  const model = scriptedModel([{promptFeedback: {blockReason: "SAFETY"}}]);
  const turn = await runToolLoop({
    callModel: model.callModel,
    runTool: () => ({}),
    contents: QUESTION,
  });
  assert.equal(turn.text, "");
  assert.equal(turn.exhausted, false);
});

test("answer text joins text parts and skips thoughts", () => {
  assert.equal(
    answerText([
      {text: "thinking...", thought: true},
      {text: "Hello "},
      {text: "there. "},
    ]),
    "Hello there.",
  );
});
