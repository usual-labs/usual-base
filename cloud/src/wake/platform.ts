/** What every wake platform module (grok-bot.ts, …) provides: how to call that platform's agent. */
export interface WakePlatform {
  id: string;
  /** What the dashboard calls it. */
  label: string;
  /** Where the person finds the address and the secret, shown on the dashboard. */
  help: string;
  /** Calls the agent once: "ok", or what went wrong. Throws for network errors. */
  deliver(target: { url: string; secret: string }, event: WakeEvent): Promise<string>;
}

/** What a woken agent receives: one new message in a room it's a member of. */
export interface WakeEvent {
  type: "usual-base.room.message";
  base: { id: string; name: string };
  room: string;
  message: { file: string; from: string; at: string; excerpt: string };
  /** The woken agent's name in rooms. */
  agent: string;
  /** The commands that read the room and answer in it, as the agent, in a clone of the Base. */
  read: string;
  reply: string;
}
