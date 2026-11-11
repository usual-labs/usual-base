// This machine's connection to the server: what it may do, and making one through the device flow.

import { call, config, DEFAULT_SERVER, fail, server, setUpCredentialHelper, token, VERSION, writeConfig } from "./core.mjs";

export const access = (token) => `${token.scope === "write" ? "read and write" : "read only"}, ${token.allBases ? "all Bases" : `${token.baseIds.length} Bases`}`;

/** The token this machine saved for this server, if any (not USUAL_BASE_TOKEN: that one isn't the machine's). */
export const savedToken = () => (config.token && (config.server || DEFAULT_SERVER) === server ? config.token : null);

const withToken = (secret, path, method = "GET") => fetch(server + path, {
  method,
  headers: { authorization: `Bearer ${secret}`, "user-agent": `usual-cli/${VERSION}` },
  signal: AbortSignal.timeout(30_000),
});

/** What a token may do (`/api/me`), or null when there is none, or it no longer works. */
export async function connection(secret = token()) {
  if (!secret) return null;
  const response = await withToken(secret, "/api/me");
  if (response.status === 401) return null; // revoked
  if (!response.ok) fail(`${server}/api/me answered HTTP ${response.status}; try again later.`);
  return response.json();
}

/**
 * Connects this machine as `name` through the device flow: the person approves it in the browser. With `again`, the
 * machine's old token was its alone, so it is revoked once the new one is saved.
 */
export async function approveMachine({ name, dir, again }) {
  const start = await call("/api/connect", { method: "POST", body: { name, kind: "agent" }, auth: false });
  console.log(`To connect "${name}", open:\n\n  ${start.verification_uri_complete}\n`);
  console.log(`and check that it shows the code ${start.user_code}. Waiting for approval…`);
  const deadline = Date.now() + start.expires_in * 1000;
  let result;
  while (Date.now() < deadline) {
    await new Promise((done) => setTimeout(done, start.interval * 1000));
    result = await call("/api/connect/token", { method: "POST", body: { device_code: start.device_code }, auth: false });
    if (result.status !== "pending") break;
  }
  if (result?.status === "denied") fail("The connection was denied.");
  if (result?.status !== "approved") fail("The code expired. Run `usual-base connect` again.");
  const old = again && savedToken() && { secret: savedToken(), name: config.name };
  Object.assign(config, { server, token: result.token, tokenId: result.token_id, name, dir, agentNames: [name] });
  writeConfig(config);
  setUpCredentialHelper();
  console.log(`\nConnected as "${name}".`);
  if (old) {
    const status = await withToken(old.secret, "/api/token/revoke", "POST").then((r) => r.status, () => 0);
    if (status === 200) console.log(`Revoked the connection it replaces, "${old.name}".`);
    else if (status !== 401) console.log(`Couldn't revoke the connection it replaces, "${old.name}"; revoke it in ${server}/agents.`);
  }
}
