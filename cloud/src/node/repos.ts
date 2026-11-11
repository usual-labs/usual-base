import { execFile, spawn } from "node:child_process";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { Readable } from "node:stream";
import { promisify } from "node:util";
import type { Repos } from "../env";

const run = promisify(execFile);

/**
 * Bases as bare repositories in a folder, served by git's own `git http-backend`. git also refuses
 * non-fast-forward pushes and deletions itself, behind the check every push already passes in `git.ts`.
 */
export function diskRepos(root: string): Repos {
  const path = (id: string) => join(root, `${id}.git`);
  return {
    async create(id, description) {
      await mkdir(root, { recursive: true });
      await run("git", ["init", "--quiet", "--bare", "--initial-branch=main", path(id)]);
      for (const [key, value] of [["receive.denyNonFastForwards", "true"], ["receive.denyDeletes", "true"]]) {
        await run("git", ["--git-dir", path(id), "config", key, value]);
      }
      await writeFile(join(path(id), "description"), description + "\n");
    },

    async delete(id) {
      await rm(path(id), { recursive: true, force: true });
    },

    async contains(id, start, wanted) {
      return run("git", ["--git-dir", path(id), "merge-base", "--is-ancestor", wanted, start]).then(() => true, () => false);
    },

    async readFile(id, file) {
      return run("git", ["--git-dir", path(id), "show", `main:${file}`], { maxBuffer: 32 * 1024 * 1024 })
        .then((result) => result.stdout, () => null);
    },

    async serve(id, request) {
      const child = spawn("git", ["http-backend"], {
        env: {
          PATH: process.env.PATH,
          GIT_PROJECT_ROOT: root,
          GIT_HTTP_EXPORT_ALL: "1",
          PATH_INFO: `/${id}.git${request.path}`,
          REQUEST_METHOD: request.method,
          QUERY_STRING: request.search.replace(/^\?/, ""),
          CONTENT_TYPE: request.headers.get("content-type") ?? "",
          HTTP_CONTENT_ENCODING: request.headers.get("content-encoding") ?? "",
          GIT_PROTOCOL: request.headers.get("git-protocol") ?? "",
          // Access was decided before this point; a user name is what lets http-backend accept pushes.
          REMOTE_USER: "usual-base",
          REMOTE_ADDR: "127.0.0.1",
        },
      });
      const stderr: Buffer[] = [];
      child.stderr.on("data", (chunk: Buffer) => stderr.push(chunk));
      child.stdin.on("error", () => {}); // git may stop reading early; its answer says why
      const body = request.body;
      if (body instanceof Uint8Array) child.stdin.end(body);
      else if (body) Readable.fromWeb(body as import("node:stream/web").ReadableStream).pipe(child.stdin);
      else child.stdin.end();
      return cgiResponse(child.stdout, () => Buffer.concat(stderr).toString(), () => child.kill());
    },
  };
}

/** Turns a CGI program's output (headers, a blank line, then the body) into a streamed Response. */
async function cgiResponse(stdout: Readable, errors: () => string, stop: () => void): Promise<Response> {
  const reader = (Readable.toWeb(stdout) as ReadableStream<Uint8Array>).getReader();
  let buffered = new Uint8Array(0);
  let end = -1;
  while (end < 0) {
    const { value, done } = await reader.read();
    if (done) return new Response(`git failed: ${errors().trim() || "no answer"}\n`, { status: 502 });
    buffered = Buffer.concat([buffered, value]);
    end = Buffer.from(buffered).indexOf("\r\n\r\n");
  }
  const headers = new Headers();
  let status = 200;
  for (const line of Buffer.from(buffered.subarray(0, end)).toString().split("\r\n")) {
    const colon = line.indexOf(":");
    if (colon < 0) continue;
    const name = line.slice(0, colon).trim();
    const value = line.slice(colon + 1).trim();
    if (name.toLowerCase() === "status") status = Number.parseInt(value, 10) || 200;
    else headers.append(name, value);
  }
  const rest = buffered.subarray(end + 4);
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      if (rest.length) controller.enqueue(rest);
    },
    async pull(controller) {
      const { value, done } = await reader.read();
      if (done) controller.close();
      else controller.enqueue(value);
    },
    cancel() {
      stop();
      return reader.cancel();
    },
  });
  return new Response(body, { status, headers });
}
