# Writing notes people read in Usual Base

People mostly read the Base in the app's View mode, which renders the Markdown. Edit mode shows the source with
its syntax dimmed. Write standard GitHub-flavoured Markdown and it will look right in both.

## Properties (front matter)

A note can start with YAML between two `---` lines. It must start on the very first line; the closing line can
also be `...`.

```markdown
---
title: Deploying the API
description: How the API reaches production, and what to check after.
tags: [ops, api]
updated: 2026-11-07
---

# Deploying the API
```

The app shows it as a card above the text:

- `title` (or `name`) is the card's heading.
- `description` (or `summary`) is the line under it.
- Other keys appear as labelled values. Lists show as chips, dates as dates, and nested keys as `parent.child`.
- If the YAML doesn't parse, the card says so. Fix it rather than leave it broken.

The app writes the front matter back exactly as it found it, comments and order included, unless a person edits
it.

## What View mode renders

| You write | People see |
|---|---|
| `#` to `######` headings | Sized headings |
| `**bold**`, `*italic*`, `~~struck~~`, `` `code` `` | Styled text |
| `[text](Other.md)`, `[text](https://…)`, bare `https://…` | Links. Notes in the Base open in the app, at the top: a `#heading` part is ignored. Web links open in the browser. |
| `-`, `*`, `1.` lists, nested by indenting | Bullets and numbers, indented. Numbering runs from the first number. |
| `- [ ] task`, `- [x] done` | Task boxes; done tasks dimmed and struck through |
| `> quote` | Quote with a bar |
| ```` ``` ```` fenced code | Monospaced block on a shaded background (no syntax colours) |
| GitHub tables, with `:---:` alignment | Real tables with borders; columns sized by their text |
| `---` on its own line, after a blank line | Horizontal rule. Directly under a line of text, `---` makes that line a heading instead. |
| `![description](images/chart.png)` | The picture, if it's a file inside the Base. Web pictures show as a link. Write spaces in the path as `%20`. |
| `<!-- comment -->` on lines of its own | Nothing. Hidden in View, visible in Edit and to agents. Text after `-->` on the same line shows as source. |
| Other HTML | Dimmed source text. Avoid it. |

Not supported: `[[wiki links]]`, footnotes and maths show as plain text, and Mermaid diagrams as code.

## Good habits

- A note's first heading usually repeats its `title`. That's fine.
- Prefer a table over aligned plain text, and a task list over "TODO" lines. Both render well.
- Keep pictures in the Base next to the notes that use them, and link them with relative paths.
- An HTML comment can carry a note for other agents that readers don't need, such as
  `<!-- Generated from deploy logs; edit the logs, not this table. -->`.
