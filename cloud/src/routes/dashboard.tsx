import { Hono, type Context } from "hono";
import { csrf } from "hono/csrf";
import { isAPIError } from "better-auth/api";
import { createAuth, sessionUser } from "../auth";
import { BaseLimitError, cleanName, createBase, deleteBase, findBase, gitURL, listBases, recentPushes, renameBase } from "../bases";
import { decide, pendingRequest } from "../connect";
import type { AppEnv, Caller, User } from "../env";
import { signupsAllow } from "../signups";
import { createToken, listTokens, revokeToken } from "../tokens";
import { SignIn, SignUp, Welcome } from "../pages/account";
import { AgentList, ConnectAgent, TokenCreated } from "../pages/agents";
import { BaseDetail, BaseList, NewBase } from "../pages/bases";
import { Approve, Decided, EnterCode } from "../pages/connect";
import { WakePage } from "../pages/wake";
import { PLATFORMS, removeWakeTarget, saveWakeTarget, wakeTargetOf, wakeTargetsOf } from "../wake";

export const dashboard = new Hono<AppEnv>();

// Cookie-authenticated form posts must come from this site: the request's own origin, which `wrangler dev`
// rewrites along with the Origin header, so it holds locally too.
dashboard.use("*", csrf());

/** A path inside this site to return to after signing in. */
const safeNext = (next: unknown) =>
  typeof next === "string" && next.startsWith("/") && !next.startsWith("//") ? next : "/";

async function signedIn(c: Context<AppEnv>): Promise<User | null> {
  return sessionUser(createAuth(c.env), c.req.raw.headers);
}

/** The signed-in person, or a redirect to sign in that comes back here. */
async function requireUser(c: Context<AppEnv>): Promise<User | Response> {
  const user = await signedIn(c);
  if (user) return user;
  const url = new URL(c.req.url);
  return c.redirect(`/sign-in?next=${encodeURIComponent(url.pathname + url.search)}`);
}

const asCaller = (user: User): Caller => ({ user, token: null });

function redirectWithCookies(to: string, headers: Headers): Response {
  const response = new Response(null, { status: 303, headers: { location: to } });
  for (const cookie of headers.getSetCookie()) response.headers.append("set-cookie", cookie);
  return response;
}

async function overLimit(c: Context<AppEnv>): Promise<boolean> {
  return !(await c.env.allowAttempt());
}

// --- Account ---------------------------------------------------------------------------------

dashboard.get("/", async (c) => {
  const user = await signedIn(c);
  if (!user) return c.html(<Welcome />);
  return c.html(<BaseList user={user} bases={await listBases(c.env, asCaller(user))} />);
});

dashboard.get("/sign-in", (c) => c.html(<SignIn next={safeNext(c.req.query("next"))} />));

dashboard.post("/sign-in", async (c) => {
  const form = await c.req.parseBody();
  const next = safeNext(form.next);
  const email = String(form.email ?? "");
  if (await overLimit(c)) return c.html(<SignIn next={next} email={email} error="Too many attempts. Try again in a minute." />, 429);
  try {
    const { headers } = await createAuth(c.env).api.signInEmail({
      body: { email, password: String(form.password ?? ""), rememberMe: true },
      returnHeaders: true,
    });
    return redirectWithCookies(next, headers);
  } catch (error) {
    if (!isAPIError(error)) throw error;
    return c.html(<SignIn next={next} email={email} error="That email and password don't match an account." />, 401);
  }
});

dashboard.get("/sign-up", (c) => c.html(<SignUp next={safeNext(c.req.query("next"))} />));

dashboard.post("/sign-up", async (c) => {
  const form = await c.req.parseBody();
  const next = safeNext(form.next);
  const name = String(form.name ?? "").trim();
  const email = String(form.email ?? "").trim();
  if (await overLimit(c)) {
    return c.html(<SignUp next={next} name={name} email={email} error="Too many attempts. Try again in a minute." />, 429);
  }
  if (!signupsAllow(c.env.SIGNUPS, email)) {
    return c.html(<SignUp next={next} name={name} email={email} error="Sign-ups aren't open yet for this email." />, 403);
  }
  try {
    const { headers } = await createAuth(c.env).api.signUpEmail({
      body: { name, email, password: String(form.password ?? "") },
      returnHeaders: true,
    });
    return redirectWithCookies(next, headers);
  } catch (error) {
    if (!isAPIError(error)) throw error;
    return c.html(<SignUp next={next} name={name} email={email} error={error.message || "Couldn't create the account."} />, 400);
  }
});

dashboard.post("/sign-out", async (c) => {
  const headers = await createAuth(c.env).api.signOut({ headers: c.req.raw.headers, returnHeaders: true })
    .then((result) => result.headers)
    .catch(() => new Headers());
  return redirectWithCookies("/", headers);
});

// --- Bases -----------------------------------------------------------------------------------

dashboard.get("/bases/new", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  return c.html(<NewBase user={user} />);
});

dashboard.post("/bases", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const name = cleanName((await c.req.parseBody()).name);
  if (!name) return c.html(<NewBase user={user} error="Give the Base a name of up to 80 characters." />, 400);
  try {
    const base = await createBase(c.env, user.id, name);
    return c.redirect(`/bases/${base.id}`, 303);
  } catch (error) {
    if (error instanceof BaseLimitError) return c.html(<NewBase user={user} error={error.message} />, 409);
    throw error;
  }
});

dashboard.get("/bases/:id", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const base = await findBase(c.env, asCaller(user), c.req.param("id"));
  if (!base) return c.notFound();
  return c.html(
    <BaseDetail user={user} base={base} git={gitURL(c.env, base.id)} pushes={await recentPushes(c.env, base.id)} />,
  );
});

dashboard.post("/bases/:id/rename", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const base = await findBase(c.env, asCaller(user), c.req.param("id"), true);
  const name = cleanName((await c.req.parseBody()).name);
  if (!base) return c.notFound();
  if (name) await renameBase(c.env, base.id, name);
  return c.redirect(`/bases/${base.id}`, 303);
});

dashboard.post("/bases/:id/delete", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const base = await findBase(c.env, asCaller(user), c.req.param("id"), true);
  if (!base) return c.notFound();
  if ((await c.req.parseBody()).confirm !== base.name) {
    return c.html(
      <BaseDetail user={user} base={base} git={gitURL(c.env, base.id)} pushes={await recentPushes(c.env, base.id)}
        error="The name didn't match, so nothing was deleted." />,
      400,
    );
  }
  await deleteBase(c.env, base.id);
  return c.redirect("/", 303);
});

// --- Agents and devices ----------------------------------------------------------------------

function chosenBases(form: Record<string, string | File | (string | File)[]>) {
  const all = form.bases !== "some";
  const picked = form.base === undefined ? [] : ([] as unknown[]).concat(form.base).map(String);
  return { allBases: all, baseIds: all ? [] : picked };
}

dashboard.get("/agents", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  return c.html(<AgentList user={user} tokens={await listTokens(c.env, user.id)} wakes={await wakeTargetsOf(c.env, user.id)} />);
});

dashboard.get("/agents/connect", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  return c.html(<ConnectAgent user={user} baseURL={c.env.BASE_URL} bases={await listBases(c.env, asCaller(user))} />);
});

dashboard.post("/agents", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const form = await c.req.parseBody({ all: true });
  const name = cleanName(form.name);
  const { allBases, baseIds } = chosenBases(form);
  if (!name || (!allBases && baseIds.length === 0)) {
    return c.html(
      <ConnectAgent user={user} baseURL={c.env.BASE_URL} bases={await listBases(c.env, asCaller(user))}
        error="Give the token a name and choose at least one Base." />,
      400,
    );
  }
  const { secret } = await createToken(c.env, {
    userId: user.id, name, kind: "agent", scope: form.write ? "write" : "read", allBases, baseIds,
  });
  c.header("cache-control", "no-store");
  return c.html(<TokenCreated user={user} name={name} secret={secret} baseURL={c.env.BASE_URL} />);
});

// --- Waking an agent that lives on another platform (src/wake/) --------------------------------

async function agentToken(c: Context<AppEnv>, userId: string) {
  const token = (await listTokens(c.env, userId)).find((t) => t.id === c.req.param("id"));
  return token?.kind === "agent" ? token : null;
}

dashboard.get("/agents/:id/wake", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const token = await agentToken(c, user.id);
  if (!token) return c.notFound();
  const target = await wakeTargetOf(c.env, user.id, token.id);
  return c.html(<WakePage user={user} token={token} target={target} platforms={Object.values(PLATFORMS)} />);
});

dashboard.post("/agents/:id/wake", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const token = await agentToken(c, user.id);
  if (!token) return c.notFound();
  const form = await c.req.parseBody();
  const error = await saveWakeTarget(c.env, user.id, token.id, {
    platform: String(form.platform ?? ""), name: cleanName(form.name) ?? token.name,
    url: String(form.url ?? "").trim(), secret: String(form.secret ?? "").trim(),
  });
  if (error) {
    const target = await wakeTargetOf(c.env, user.id, token.id);
    return c.html(<WakePage user={user} token={token} target={target} platforms={Object.values(PLATFORMS)} error={error} />, 400);
  }
  return c.redirect("/agents", 303);
});

dashboard.post("/agents/:id/wake/delete", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  await removeWakeTarget(c.env, user.id, c.req.param("id"));
  return c.redirect("/agents", 303);
});

dashboard.post("/agents/:id/revoke", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  await revokeToken(c.env, user.id, c.req.param("id"));
  return c.redirect("/agents", 303);
});

// --- Approving a connection (device flow) ----------------------------------------------------

dashboard.get("/connect", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const code = c.req.query("code");
  if (!code) return c.html(<EnterCode user={user} />);
  const request = await pendingRequest(c.env, code);
  if (!request) return c.html(<EnterCode user={user} error="That code isn't valid any more. Start again in the app or agent." />, 404);
  return c.html(
    <Approve user={user} code={request.userCode} clientName={request.clientName} kind={request.kind}
      bases={await listBases(c.env, asCaller(user))} />,
  );
});

dashboard.post("/connect", async (c) => {
  const user = await requireUser(c);
  if (user instanceof Response) return user;
  const form = await c.req.parseBody({ all: true });
  const code = String(form.code ?? "");
  const request = await pendingRequest(c.env, code);
  if (!request) return c.html(<EnterCode user={user} error="That code isn't valid any more. Start again in the app or agent." />, 404);
  if (form.decision !== "approve") {
    await decide(c.env, code, user.id, { approve: false });
    return c.html(<Decided user={user} approved={false} />);
  }
  const choice = request.kind === "device"
    ? { scope: "write" as const, allBases: true, baseIds: [] }
    : { scope: form.write ? ("write" as const) : ("read" as const), ...chosenBases(form) };
  await decide(c.env, code, user.id, { approve: true, ...choice });
  return c.html(<Decided user={user} approved={true} />);
});
