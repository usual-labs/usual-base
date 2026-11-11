// Grok Bot (xAI and Cursor): a Bot runs a routine when its webhook is called. POST the routine's "POST to"
// address with `Authorization: Bearer <key>` and a JSON body, which "the Bot receives … with the routine
// instruction"; 200 means a run started, anything else that none did, and failed runs aren't retried
// (cursor.com/help/grok-bot/routines, read 2026-11-11). Limits: 200 runs an hour per routine.

import type { WakePlatform } from "./platform";

export const grokBot: WakePlatform = {
  id: "grok-bot",
  label: "Grok Bot routine",
  help: "In the Bot's chat, ask it to add a webhook trigger to the routine that answers your rooms. Then copy the " +
    "routine's “POST to” address and its key from the routine's details.",
  async deliver(target, event) {
    const response = await fetch(target.url, {
      method: "POST",
      headers: { authorization: `Bearer ${target.secret}`, "content-type": "application/json" },
      body: JSON.stringify(event),
    });
    return response.status === 200 ? "ok" : `HTTP ${response.status}`;
  },
};
