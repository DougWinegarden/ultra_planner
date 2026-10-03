/**
 * One Quackers turn with tools: ask the model, run whatever tools it calls,
 * send the results back, and repeat until it answers in plain text.
 *
 * Split out from index.js so the loop can be tested with a fake model: the
 * Gemini HTTP call is passed in as `callModel`, and the tools as `runTool`.
 */

/** Most model calls in one turn, so a confused model cannot loop forever. */
const MAX_TOOL_STEPS = 6;

/**
 * @param {object} options
 * @param {function(Array): Promise<object>} options.callModel Sends the
 *     contents so far and resolves to the raw generateContent response body.
 * @param {function(string, object): object} options.runTool Runs one tool
 *     call and returns its response object. Must not throw.
 * @param {Array} options.contents Conversation so far, ending with the user's
 *     new message.
 * @param {number} [options.maxSteps] Cap on model calls.
 * @return {Promise<{text: string, steps: number, exhausted: boolean}>} The
 *     final answer; text is empty if the model never gave one.
 */
async function runToolLoop({
  callModel,
  runTool,
  contents,
  maxSteps = MAX_TOOL_STEPS,
}) {
  const history = contents.slice();

  for (let step = 1; step <= maxSteps; step++) {
    const body = await callModel(history);
    const content = body &&
      Array.isArray(body.candidates) &&
      body.candidates[0] &&
      body.candidates[0].content;
    const parts = content && Array.isArray(content.parts) ? content.parts : [];
    const calls = parts.filter((part) => part && part.functionCall);

    if (calls.length === 0) {
      return {text: answerText(parts), steps: step, exhausted: false};
    }

    // Sent back exactly as received: Gemini 3 attaches thought signatures to
    // these parts and rejects a follow-up request that drops them.
    history.push({...content, role: "model"});
    history.push({
      role: "user",
      // One response per call, in the same order, as parallel calls require.
      parts: calls.map((part) => {
        const call = part.functionCall;
        const response = {
          name: call.name,
          response: runTool(call.name, call.args || {}),
        };
        if (call.id) response.id = call.id;
        return {functionResponse: response};
      }),
    });
  }

  return {text: "", steps: maxSteps, exhausted: true};
}

/**
 * Joins the visible text parts of a reply, skipping any thought summaries.
 *
 * @param {Array} parts Content parts from the model.
 * @return {string} The answer, trimmed.
 */
function answerText(parts) {
  return parts
    .filter((part) => part && typeof part.text === "string" && !part.thought)
    .map((part) => part.text)
    .join("")
    .trim();
}

module.exports = {MAX_TOOL_STEPS, runToolLoop, answerText};
