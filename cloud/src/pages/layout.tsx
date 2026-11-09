import type { Child } from "hono/jsx";
import type { User } from "../env";

const css = `
:root { color-scheme: light dark; --bg: #fbfaf8; --card: #ffffff; --text: #1d1d1f; --muted: #6e6e73;
  --line: #e6e3de; --accent: #2f6f5e; --danger: #b3261e; --code: #f3f1ed; }
@media (prefers-color-scheme: dark) { :root { --bg: #161616; --card: #1f1f1f; --text: #f2f2f2; --muted: #a1a1a6;
  --line: #333; --accent: #7cc4ad; --danger: #ff8a80; --code: #2a2a2a; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font: 16px/1.5 -apple-system, BlinkMacSystemFont,
  "Segoe UI", system-ui, sans-serif; }
header { display: flex; align-items: center; gap: 20px; padding: 16px; max-width: 880px; margin: 0 auto; }
header a.brand { font-weight: 650; color: var(--text); text-decoration: none; margin-right: auto; }
header nav { display: flex; gap: 16px; align-items: center; }
main { max-width: 880px; margin: 0 auto; padding: 8px 16px 64px; }
a { color: var(--accent); }
h1 { font-size: 28px; line-height: 1.2; margin: 24px 0 8px; }
h2 { font-size: 19px; margin: 32px 0 8px; }
p.muted, .muted { color: var(--muted); }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 16px; margin: 12px 0; }
.row { display: flex; justify-content: space-between; align-items: center; gap: 12px; flex-wrap: wrap; }
.list { list-style: none; padding: 0; margin: 0; }
.list li { padding: 12px 0; border-bottom: 1px solid var(--line); }
.list li:last-child { border-bottom: 0; }
code, pre { font: 13px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace; background: var(--code);
  border-radius: 6px; }
code { padding: 1px 5px; overflow-wrap: anywhere; }
pre { padding: 12px; overflow-x: auto; white-space: pre-wrap; word-break: break-all; }
form.stack { display: grid; gap: 12px; max-width: 420px; }
label { display: grid; gap: 4px; font-weight: 550; }
label.inline { display: flex; gap: 8px; align-items: center; font-weight: 400; }
input[type=text], input[type=email], input[type=password] { font: inherit; padding: 9px 11px;
  border: 1px solid var(--line); border-radius: 8px; background: var(--card); color: var(--text); }
button, .button { font: inherit; font-weight: 550; padding: 8px 16px; border-radius: 8px; border: 1px solid var(--accent);
  background: var(--accent); color: #fff; cursor: pointer; text-decoration: none; display: inline-block; }
@media (prefers-color-scheme: dark) { button, .button { color: #111; } }
button.secondary, .button.secondary { background: transparent; color: var(--accent); }
button.danger { background: transparent; border-color: var(--danger); color: var(--danger); }
button.link { background: none; border: 0; color: var(--accent); padding: 0; font-weight: 400; }
.error { color: var(--danger); }
.code { font: 600 30px/1.2 ui-monospace, Menlo, monospace; letter-spacing: 2px; }
fieldset { border: 1px solid var(--line); border-radius: 8px; padding: 8px 12px; display: grid; gap: 6px; }
legend { font-weight: 550; padding: 0 4px; }
`;

export function Page(props: { title: string; user?: User | null; children: Child }) {
  return (
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{props.title === "Usual Base" ? "Usual Base" : `${props.title} · Usual Base`}</title>
        <style dangerouslySetInnerHTML={{ __html: css }} />
      </head>
      <body>
        <header>
          <a class="brand" href="/">Usual Base</a>
          {props.user ? (
            <nav>
              <a href="/">Bases</a>
              <a href="/agents">Agents and devices</a>
              <form method="post" action="/sign-out" style="margin:0">
                <button class="link" type="submit">Sign out</button>
              </form>
            </nav>
          ) : (
            <nav>
              <a href="/sign-in">Sign in</a>
            </nav>
          )}
        </header>
        <main>{props.children}</main>
      </body>
    </html>
  );
}

export function when(time: number | null): string {
  if (!time) return "never";
  const seconds = Math.round((Date.now() - time) / 1000);
  if (seconds < 60) return "just now";
  if (seconds < 3600) return `${Math.round(seconds / 60)} min ago`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)} h ago`;
  return new Date(time).toISOString().slice(0, 10);
}
