import type { Repos } from "../env";

const upstreamCache = new Map<string, { token: string; remote: string; expiresAt: number }>();

/** Bases as Cloudflare Artifacts repositories. Clients never see Artifacts tokens; requests get short-lived ones. */
export function artifactsRepos(artifacts: Artifacts): Repos {
  return {
    async create(id, description) {
      // The repository's own write token is returned and dropped: clients only ever see Usual Base tokens.
      await artifacts.create(id, { description });
    },

    async delete(id) {
      await artifacts.delete(id).catch((error: { code?: string }) => {
        if (error?.code !== "NOT_FOUND") throw error;
      });
    },

    async contains(id, start, wanted) {
      using repo = await artifacts.get(id);
      for (let offset = 0; offset < 10_000; offset += 1000) {
        const page = await repo.log({ ref: start, limit: 1000, offset }).catch(() => []);
        if (page.some((commit) => commit.hash === wanted)) return true;
        if (page.length < 1000) return false;
      }
      return false;
    },

    async serve(id, request) {
      const upstream = await upstreamFor(artifacts, id, request.write ? "write" : "read");
      const headers = new Headers();
      for (const name of ["content-type", "accept", "git-protocol", "user-agent"]) {
        const value = request.headers.get(name);
        if (value) headers.set(name, value);
      }
      headers.set("authorization", `Bearer ${upstream.token}`);
      return fetch(`${upstream.remote}${request.path}${request.search}`, {
        method: request.method, headers, body: request.body,
      });
    },
  };
}

async function upstreamFor(artifacts: Artifacts, id: string, scope: "read" | "write") {
  const key = `${id}:${scope}`;
  const cached = upstreamCache.get(key);
  if (cached && cached.expiresAt - Date.now() > 5 * 60_000) return cached;
  using repo = await artifacts.get(id);
  const [minted, info] = await Promise.all([repo.createToken(scope, 3600), repo.info()]);
  const entry = { token: minted.plaintext, remote: info.remote, expiresAt: Date.parse(minted.expiresAt) };
  upstreamCache.set(key, entry);
  return entry;
}
