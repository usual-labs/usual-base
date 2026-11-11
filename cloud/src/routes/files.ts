import { Hono } from "hono";
import type { AppEnv } from "../env";
import { assets, cli, installScript, skill } from "../generated/files";

/** The CLI, its installer, the agent skill and the dashboard's assets, served from this repository's own files. */
export const files = new Hono<AppEnv>();

const decoded = new Map<string, ArrayBuffer>();

/** cloud/assets, by content-hashed path, so a browser keeps each one until it changes. */
files.get("/assets/*", (c) => {
  const asset = (assets as Record<string, { type: string; body: string } | undefined>)[c.req.path];
  if (!asset) return c.notFound();
  let bytes = decoded.get(c.req.path);
  if (!bytes) decoded.set(c.req.path, (bytes = Uint8Array.from(atob(asset.body), (ch) => ch.charCodeAt(0)).buffer as ArrayBuffer));
  return c.body(bytes, 200, { "content-type": asset.type, "cache-control": "public, max-age=31536000, immutable" });
});

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
