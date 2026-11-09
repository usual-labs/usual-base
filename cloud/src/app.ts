import { Hono } from "hono";
import type { AppEnv } from "./env";
import { handleGit } from "./git";
import { api } from "./routes/api";
import { dashboard } from "./routes/dashboard";
import { files } from "./routes/files";

/** The whole service, for any platform: each entry point passes its own `Env` to `app.fetch`. */
export const app = new Hono<AppEnv>();
app.all("/git/*", (c) => handleGit(c.req.raw, c.env));
app.route("/api", api);
app.route("/", files);
app.route("/", dashboard);
app.notFound((c) => c.text("Not found", 404));
