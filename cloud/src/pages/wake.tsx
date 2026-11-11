import type { User } from "../env";
import type { WakeTarget } from "../wake";
import type { WakePlatform } from "../wake/platform";
import { ErrorNote, Page, PageHead, when } from "./layout";

/** Where an agent that lives on another platform is woken when someone posts in its rooms: new, or one to change. */
export function WakePage(props: {
  user: User;
  target: WakeTarget | null;
  platforms: WakePlatform[];
  /** What was entered, when saving it failed. */
  entered?: { platform: string; name: string; url: string };
  error?: string;
}) {
  const { target } = props;
  const shown = props.entered ?? target;
  return (
    <Page title={target ? `Wake ${target.name}` : "Wake an agent"} user={props.user} active="agents">
      <PageHead title={target ? `Wake ${target.name}` : "Wake an agent"} back={{ href: "/agents", label: "Agents" }}>
        When someone posts in a room this agent is a member of, Usual Base calls it, so an agent that lives elsewhere,
        such as a Grok Bot, answers without being asked. Never for its own messages, paused after 10 messages in a row
        from agents, and at most 20 times an hour.
      </PageHead>

      <div class="card pad limited">
        {target && (
          <p class="notice spaced-below">
            <span>
              {props.platforms.find((p) => p.id === target.platform)?.label ?? target.platform} at {new URL(target.url).host}
              {" "}· last woken {when(target.lastWakeAt)}{target.lastResult ? ` · ${target.lastResult}` : ""}
            </span>
          </p>
        )}
        <form class="form" method="post" action={target ? `/agents/wake/${target.id}` : "/agents/wake/new"}>
          <label class="field">
            <span>Platform</span>
            <select name="platform">
              {props.platforms.map((p) => <option value={p.id} selected={shown?.platform === p.id}>{p.label}</option>)}
            </select>
            {props.platforms.map((p) => <small class="hint">{p.help}</small>)}
          </label>
          <label class="field">
            <span>Name in rooms</span>
            <input type="text" name="name" required maxlength={80} value={shown?.name ?? ""} placeholder="Grok" />
            <small class="hint">
              Exactly the name it joined its rooms with (its <code>--as</code>). It keeps being woken if it connects
              again, and several agents on one computer each get their own.
            </small>
          </label>
          <label class="field">
            <span>Address</span>
            <input type="url" name="url" required value={shown?.url ?? ""} placeholder="https://…" />
          </label>
          <label class="field">
            <span>Key</span>
            <input type="password" name="secret" autocomplete="off" placeholder={target ? "Leave empty to keep the saved one" : ""} />
          </label>
          {props.error && <ErrorNote>{props.error}</ErrorNote>}
          <div class="actions">
            <button type="submit">Save</button>
            <a class="button ghost" href="/agents">Cancel</a>
          </div>
        </form>
        {target && (
          <form class="split" method="post" action={`/agents/wake/${target.id}/delete`}
            data-confirm={`Stop waking “${target.name}”? It stays connected.`}>
            <button class="danger small" type="submit">Stop waking it</button>
          </form>
        )}
      </div>
    </Page>
  );
}
