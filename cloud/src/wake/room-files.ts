// Where the CLI keeps room files (cli/lib/room-store.mjs and the skill's references/rooms.md), so the server can
// read a message and a member without a clone. `slug` must stay the CLI's.

export const ROOM_NAME = /^[^/\\:*?"<>|.][^/\\:*?"<>|]{0,99}$/;
export const MESSAGE_FILE = /^(\d{4}-\d{2}-\d{2})T\d{2}-\d{2}-\d{2}\.\d{3}Z_[a-z0-9-]+_[0-9a-z]{1,8}\.md$/;

export const slug = (name: string) =>
  name.toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
    .slice(0, 32) || "someone";

export const messagePath = (room: string, file: string) => `Rooms/${room}/${file.slice(0, 10)}/${file}`;
export const memberPath = (room: string, name: string) => `Rooms/${room}/members/${slug(name)}.md`;

/** One field of a file's front matter, unquoted, or null. */
export function frontMatter(text: string, field: string): string | null {
  const block = text.match(/^---\r?\n([\s\S]*?)\r?\n---/)?.[1];
  const line = block?.split(/\r?\n/).find((l) => l.startsWith(`${field}:`));
  if (!line) return null;
  const value = line.slice(field.length + 1).trim();
  if (value.startsWith('"')) {
    try {
      return JSON.parse(value);
    } catch {}
  }
  return value;
}
