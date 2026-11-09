// pako's low-level zlib, because its Inflate class reads concatenated streams as one: in a pack, each
// object is its own stream, and the parser has to stop exactly where one ends.
import zlib from "pako/lib/zlib/inflate.js";
import ZStream from "pako/lib/zlib/zstream.js";

export const ZERO_ID = "0".repeat(40);

export interface RefUpdate {
  oldId: string;
  newId: string;
  ref: string;
}

/** The ref updates at the start of a receive-pack request, and where the pack data begins. */
export function readCommands(bytes: Uint8Array): { commands: RefUpdate[]; packStart: number; sideband: boolean } {
  const commands: RefUpdate[] = [];
  const text = new TextDecoder();
  let sideband = false;
  let offset = 0;
  while (offset + 4 <= bytes.length) {
    const length = parseInt(text.decode(bytes.subarray(offset, offset + 4)), 16);
    if (!Number.isFinite(length)) break;
    if (length === 0) {
      offset += 4;
      break;
    }
    const [line, capabilities] = text.decode(bytes.subarray(offset + 4, offset + length)).split("\0");
    if (capabilities !== undefined) sideband = capabilities.includes("side-band");
    const [oldId, newId, ref] = line.trim().split(" ");
    if (oldId && newId && ref) commands.push({ oldId, newId, ref });
    offset += length;
  }
  return { commands, packStart: offset, sideband };
}

/**
 * Commit ids in a pack, each with its parents. `complete` is false when the pack holds deltas, which
 * might be commits this can't read without resolving their bases.
 */
export async function packCommits(bytes: Uint8Array): Promise<{ commits: Map<string, string[]>; complete: boolean }> {
  const commits = new Map<string, string[]>();
  if (bytes.length < 12) return { commits, complete: true };
  if (new TextDecoder().decode(bytes.subarray(0, 4)) !== "PACK") return { commits, complete: false };
  const count = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(8);
  let offset = 12;
  let complete = true;
  for (let i = 0; i < count; i++) {
    let byte = bytes[offset++];
    const type = (byte >> 4) & 7;
    let size = byte & 15;
    let shift = 4;
    while (byte & 0x80) {
      byte = bytes[offset++];
      size += (byte & 0x7f) * 2 ** shift;
      shift += 7;
    }
    if (type === 6) {
      do byte = bytes[offset++];
      while (byte & 0x80);
    }
    if (type === 7) offset += 20;
    // Every object is inflated, if only to find where it ends; only commits are kept.
    const object = inflateAt(bytes, offset, size);
    if (!object) return { commits, complete: false };
    offset = object.end;
    const keep = type === 1;
    if (keep) {
      const data = object.data;
      const header = new TextEncoder().encode(`commit ${data.length}\0`);
      const id = hex(await crypto.subtle.digest("SHA-1", concat([header, data])));
      const parents = [...new TextDecoder().decode(data).matchAll(/^parent ([0-9a-f]{40})$/gm)].map((m) => m[1]);
      commits.set(id, parents);
    } else if (type === 6 || type === 7) {
      complete = false;
    }
  }
  return { commits, complete };
}

/** Inflates the zlib stream at `offset`, whose output is `size` bytes; returns it and where the stream ends. */
function inflateAt(bytes: Uint8Array, offset: number, size: number): { data: Uint8Array; end: number } | null {
  const stream = new ZStream();
  if (zlib.inflateInit(stream) !== 0) return null;
  stream.input = bytes;
  stream.next_in = offset;
  stream.avail_in = bytes.length - offset;
  stream.output = new Uint8Array(Math.max(size, 1));
  stream.next_out = 0;
  stream.avail_out = stream.output.length;
  const status = zlib.inflate(stream, 4 /* Z_FINISH */);
  zlib.inflateEnd(stream);
  if (status !== 1 /* Z_STREAM_END */ || stream.next_out !== size) return null;
  return { data: stream.output.subarray(0, size), end: stream.next_in };
}

/**
 * Whether `newId` descends from `oldId`, following commits in the pack, then asking `serverHas`
 * about commits the server already had.
 */
export async function isFastForward(
  update: RefUpdate,
  commits: Map<string, string[]>,
  serverHistoryContains: (startId: string, wantedId: string) => Promise<boolean>,
): Promise<boolean> {
  const seen = new Set<string>();
  const frontier = [update.newId];
  const outside: string[] = [];
  while (frontier.length) {
    const id = frontier.pop()!;
    if (id === update.oldId) return true;
    if (seen.has(id)) continue;
    seen.add(id);
    const parents = commits.get(id);
    if (parents) frontier.push(...parents);
    else outside.push(id);
  }
  for (const id of outside) {
    if (await serverHistoryContains(id, update.oldId)) return true;
  }
  return false;
}

/** A receive-pack result that refuses or accepts each update, the way a git server reports it. */
export function reportStatus(results: { ref: string; error: string | null }[], sideband: boolean): Uint8Array {
  const encoder = new TextEncoder();
  const pkt = (line: string) => encoder.encode((line.length + 4).toString(16).padStart(4, "0") + line);
  const lines = ["unpack ok\n", ...results.map((r) => (r.error ? `ng ${r.ref} ${r.error}\n` : `ok ${r.ref}\n`))];
  const report = concat([...lines.map(pkt), encoder.encode("0000")]);
  if (!sideband) return report;
  const band = concat([new Uint8Array([1]), report]);
  return concat([encoder.encode((band.length + 4).toString(16).padStart(4, "0")), band, encoder.encode("0000")]);
}

export function hex(buffer: ArrayBuffer): string {
  return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function concat(parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}
