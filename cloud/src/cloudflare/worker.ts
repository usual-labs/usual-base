// The Cloudflare entry point (base.usual.dev): D1 for the database, Artifacts for the repositories, a Durable
// Object per Base for live updates, and Workers rate limiting for sign-in attempts.

import { drizzle } from "drizzle-orm/d1";
import { app } from "../app";
import { schema } from "../db";
import type { Env } from "../env";
import { artifactsRepos } from "./artifacts";
import type { BaseRoom } from "./room";

export { BaseRoom } from "./room";

interface Bindings {
  DB: D1Database;
  ARTIFACTS: Artifacts;
  BASE_ROOM: DurableObjectNamespace<BaseRoom>;
  AUTH_LIMIT: RateLimit;
  BASE_URL: string;
  BETTER_AUTH_SECRET: string;
  SIGNUPS?: string;
}

export default {
  fetch(request, bindings, ctx) {
    const room = (baseId: string) => bindings.BASE_ROOM.get(bindings.BASE_ROOM.idFromName(baseId));
    const env: Env = {
      BASE_URL: bindings.BASE_URL,
      BETTER_AUTH_SECRET: bindings.BETTER_AUTH_SECRET,
      SIGNUPS: bindings.SIGNUPS,
      db: drizzle(bindings.DB, { schema }),
      repos: artifactsRepos(bindings.ARTIFACTS),
      publish: (event) => room(event.base).broadcast(event),
      watch: (baseId, request) => room(baseId).fetch(request),
      allowAttempt: async () =>
        (await bindings.AUTH_LIMIT.limit({ key: request.headers.get("cf-connecting-ip") ?? "local" })).success,
      background: (work) => ctx.waitUntil(work),
    };
    return app.fetch(request, env, ctx);
  },
} satisfies ExportedHandler<Bindings>;
