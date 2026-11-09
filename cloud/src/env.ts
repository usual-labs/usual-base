import type { Database } from "./db";

/**
 * What the app needs from the platform it runs on. Each platform builds one per request: Cloudflare in
 * `src/cloudflare/worker.ts`, Node (and so Docker) in `src/node/server.ts`.
 */
export interface Env {
  /** This server's public origin, e.g. "https://base.usual.dev". */
  BASE_URL: string;
  BETTER_AUTH_SECRET: string;
  /** Who may create an account: "open", or a comma-separated list of emails. Unset: nobody. */
  SIGNUPS?: string;
  db: Database;
  repos: Repos;
  /** Tells every app watching the Base about a push. */
  publish(event: PushedEvent): Promise<void>;
  /** Answers an already authorized request to watch a Base's pushes over a WebSocket. */
  watch(baseId: string, request: Request): Promise<Response>;
  /** False once this client has tried to sign in or up too often. */
  allowAttempt(): Promise<boolean>;
  /** Keeps work running after the response has been sent. */
  background(work: Promise<unknown>): void;
}

/** The git repositories behind Bases, one per Base, named after its id. */
export interface Repos {
  create(id: string, description: string): Promise<void>;
  /** Deletes the repository; one that doesn't exist is fine. */
  delete(id: string): Promise<void>;
  /** Whether commit `wanted` is in the history of commit `start`. */
  contains(id: string, start: string, wanted: string): Promise<boolean>;
  /** Answers a git smart-HTTP request; `path` is what follows `<id>.git`, such as "/info/refs". */
  serve(id: string, request: GitRequest): Promise<Response>;
}

export interface GitRequest {
  method: string;
  path: string;
  /** The query string with its "?", or "". */
  search: string;
  headers: Headers;
  body: ReadableStream<Uint8Array> | Uint8Array | null;
  write: boolean;
}

export interface PushedEvent {
  type: "pushed";
  base: string;
  ref: string;
  after: string;
  by: string;
  at: number;
}

export interface User {
  id: string;
  name: string;
  email: string;
}

/** Who a request acts for: a signed-in person in the dashboard, or a token. */
export interface Caller {
  user: User;
  token: TokenInfo | null;
}

export interface TokenInfo {
  id: string;
  name: string;
  kind: "agent" | "device";
  scope: "read" | "write";
  allBases: boolean;
  baseIds: string[];
}

export type AppEnv = { Bindings: Env; Variables: { caller: Caller | null } };
