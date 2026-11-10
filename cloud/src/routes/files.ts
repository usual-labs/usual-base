import { Hono } from "hono";
import type { AppEnv } from "../env";
import { cli, installScript, skill } from "../generated/files";

/** The CLI, its installer and the agent skill, served from this repository's own files. */
export const files = new Hono<AppEnv>();

files.get("/install.sh", (c) =>
  c.body(installScript.replaceAll("https://base.usual.dev", c.env.BASE_URL), 200, {
    "content-type": "text/x-shellscript; charset=utf-8",
  }),
);

files.get("/cli/usual-base.mjs", (c) =>
  c.body(cli.replace('"https://base.usual.dev"', JSON.stringify(c.env.BASE_URL)), 200, {
    "content-type": "text/javascript; charset=utf-8",
  }),
);

files.get("/skill.json", (c) => c.json({ name: "usual-base", files: skill }));
