import type { Child } from "hono/jsx";
import { raw } from "hono/html";
import type { User } from "../env";
import { assetPath } from "../generated/files";

const asset = (name: string) => (assetPath as Record<string, string>)[name];
const REPO = "https://github.com/usual-labs/usual-base";

/**
 * Every dashboard page: the header with the wordmark and, signed in, the two sections; the page; a quiet footer.
 * The look is cloud/assets/app.css. `narrow` centres a single panel, as for signing in.
 */
export function Page(props: {
  title: string;
  user?: User | null;
  active?: "bases" | "agents";
  narrow?: boolean;
  children: Child;
}) {
  const { user, active } = props;
  return (
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{props.title === "Usual Base" ? "Usual Base" : `${props.title} · Usual Base`}</title>
        <meta name="description" content="A shared knowledge base for you and your agents." />
        <meta name="color-scheme" content="light dark" />
        <meta name="theme-color" content="#f6f7f8" media="(prefers-color-scheme: light)" />
        <meta name="theme-color" content="#0a0b0d" media="(prefers-color-scheme: dark)" />
        <link rel="icon" href={asset("icon-64.png")} type="image/png" />
        <link rel="apple-touch-icon" href={asset("icon-256.png")} />
        <link rel="preload" href={asset("fonts/Figtree-latin.woff2")} as="font" type="font/woff2" crossorigin="anonymous" />
        <link rel="stylesheet" href={asset("app.css")} />
        {raw(`<script>document.documentElement.classList.add("js")</script>`)}
        <script src={asset("app.js")} defer />
      </head>
      <body>
        <header class="top">
          <div class="top-inner">
            <a class="brand" href="/" aria-label="Usual Base">
              <img src={asset("icon-64.png")} alt="" width="28" height="28" />
              <span class="wordmark">Usual<span>base</span></span>
            </a>
            {user ? (
              <>
                <nav class="nav" aria-label="Sections">
                  <a href="/" aria-current={active === "bases" ? "page" : undefined}>Bases</a>
                  <a href="/agents" aria-current={active === "agents" ? "page" : undefined}>Agents</a>
                </nav>
                <div class="who">
                  <span class="name">{user.name}</span>
                  <form method="post" action="/sign-out">
                    <button class="ghost small" type="submit">Sign out</button>
                  </form>
                </div>
              </>
            ) : (
              <a class="button secondary small" href="/sign-in">Sign in</a>
            )}
          </div>
        </header>
        <main class={props.narrow ? "narrow" : undefined}>{props.children}</main>
        <footer class="foot">
          <span>Usual Base</span>
          <span>
            <a href={`${REPO}/tree/main/docs/onboarding`}>Agent guides</a> · <a href={REPO}>Open source on GitHub</a>
          </span>
        </footer>
      </body>
    </html>
  );
}

/** A page's title, with an optional way back, a description and actions on the right. */
export function PageHead(props: { title: Child; back?: { href: string; label: string }; actions?: Child; children?: Child }) {
  return (
    <div class="head">
      <div>
        {props.back && (
          <a class="crumb" href={props.back.href}>
            <Icon name="back" size={16} />
            {props.back.label}
          </a>
        )}
        <h1>{props.title}</h1>
        {props.children && <p>{props.children}</p>}
      </div>
      {props.actions && <div class="actions">{props.actions}</div>}
    </div>
  );
}

/**
 * Text to copy: a prompt, a command or a token, with a Copy button where the script runs. A `caption` puts the
 * button in a bar above the text (for long text); without one it sits at the end of a single line.
 */
export function CopyBlock(props: { text: string; caption?: string; tall?: boolean; label?: string; class?: string }) {
  const classes = ["copy", props.caption ? "barred" : "short", props.tall && "tall", props.class].filter(Boolean).join(" ");
  const button = (
    <button class="secondary small" type="button" aria-label={props.label ?? "Copy"}>
      <Icon name="copy" size={15} />
      <span>Copy</span>
    </button>
  );
  return (
    <div class={classes}>
      {props.caption && <div class="copy-bar"><span>{props.caption}</span>{button}</div>}
      <pre>{props.text}</pre>
      {!props.caption && button}
    </div>
  );
}

export function ErrorNote(props: { children: Child }) {
  return (
    <p class="error" role="alert">
      <Icon name="alert" size={16} />
      <span>{props.children}</span>
    </p>
  );
}

const ICONS = {
  back: "M15 18l-6-6 6-6",
  chevron: "M9 6l6 6-6 6",
  plus: "M12 5v14M5 12h14",
  copy: "M9 9h10v10H9zM5 15V5h10",
  check: "M5 12.5l4.5 4.5L19 7.5",
  close: "M6 6l12 12M18 6L6 18",
  alert: "M12 8v5M12 16.5v.5M12 3l9.5 17h-19z",
  laptop: "M4 6h16v10H4zM2 19h20",
  terminal: "M4 5h16v14H4zM8 10l3 2-3 2M13 14h3",
  bot: "M6 9h12v10H6zM12 5v4M9.5 13.5v1M14.5 13.5v1M3 13v3M21 13v3",
  cloud: "M7 18h10.5a4 4 0 0 0 .5-7.97A6 6 0 0 0 6.34 11.1 3.5 3.5 0 0 0 7 18z",
  key: "M14 10a4 4 0 1 0-1.2 2.85L20 20M17 17l2-2",
  bell: "M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15zM10 21h4",
  git: "M6 4v10M6 20a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM18 10a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM18 10c0 5-6 4-12 6",
  folder: "M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z",
  history: "M3 12a9 9 0 1 0 3-6.7M3 4v4h4M12 7v5l3 2",
} as const;

/** A simple line icon in the text's colour. */
export function Icon(props: { name: keyof typeof ICONS; size?: number; class?: string }) {
  const size = props.size ?? 18;
  return (
    <svg class={props.class} width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d={ICONS[props.name]} />
    </svg>
  );
}

/** The app icon, for empty states and the welcome page. */
export const AppMark = (props: { class?: string; size: number }) => (
  <img class={props.class ?? "mark"} src={asset("icon-256.png")} alt="" width={props.size} height={props.size} />
);

export function when(time: number | null): string {
  if (!time) return "never";
  const seconds = Math.round((Date.now() - time) / 1000);
  if (seconds < 60) return "just now";
  if (seconds < 3600) return `${Math.round(seconds / 60)} min ago`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)} h ago`;
  return new Date(time).toISOString().slice(0, 10);
}
