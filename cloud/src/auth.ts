import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { account, session, user, verification } from "./db";
import type { Env, User } from "./env";

/** Better Auth for people signing in to the dashboard, with email and password. */
export function createAuth(env: Env) {
  return betterAuth({
    database: drizzleAdapter(env.db, { provider: "sqlite", schema: { user, session, account, verification } }),
    secret: env.BETTER_AUTH_SECRET,
    baseURL: env.BASE_URL,
    emailAndPassword: { enabled: true, minPasswordLength: 10 },
    session: { expiresIn: 60 * 60 * 24 * 30, updateAge: 60 * 60 * 24 },
    // Forms post to this Worker's own routes, which call auth.api directly; the HTTP handler isn't mounted.
    rateLimit: { enabled: false },
  });
}

export type Auth = ReturnType<typeof createAuth>;

export async function sessionUser(auth: Auth, headers: Headers): Promise<User | null> {
  const session = await auth.api.getSession({ headers });
  if (!session) return null;
  const { id, name, email } = session.user;
  return { id, name, email };
}
