import type { Base } from "../bases";
import type { User } from "../env";
import type { TokenListing } from "../tokens";
import { PLATFORMS, type WakeTarget } from "../wake";
import { CopyBlock, ErrorNote, Icon, Page, PageHead, when } from "./layout";
import { connectPrompts } from "./prompts";

const GUIDES = "https://github.com/usual-labs/usual-base/tree/main/docs/onboarding";

function access(token: TokenListing) {
  const what = token.allBases ? "all Bases" : token.baseNames || "no Bases";
  return `${token.scope === "write" ? "Read and write" : "Read only"} · ${what}`;
}

/** A wake target's last result, as a dot and words: fine, failed, or not woken (and why). */
function Result(props: { target: WakeTarget }) {
  const result = props.target.lastResult;
  const state = !result ? "" : result.startsWith("woken") ? "ok" : result.startsWith("not woken") ? "" : "bad";
  return (
    <span class="badge"><span class={`dot ${state}`} />{result ?? "not woken yet"}</span>
  );
}

export function AgentList(props: { user: User; tokens: TokenListing[]; wakes: WakeTarget[] }) {
  return (
    <Page title="Agents" user={props.user} active="agents">
      <PageHead
        title="Agents"
        actions={<a class="button" href="/agents/connect"><Icon name="plus" size={16} />Connect an agent</a>}
      >
        Everything connected to your Bases. Each connection has its own token, so you can revoke one without the
        others; agents on one machine share its connection.
      </PageHead>

      <section class="section">
        <header><h2>Connections</h2></header>
        {props.tokens.length === 0 ? (
          <div class="empty">
            <p>Nothing connected yet. Connect an agent, or sign in from the Mac app.</p>
            <a class="button secondary" href="/agents/connect">Connect an agent</a>
          </div>
        ) : (
          <div class="card">
            <ul class="rows">
              {props.tokens.map((token) => (
                <li class="row">
                  <span class="avatar"><Icon name={token.kind === "device" ? "laptop" : "terminal"} /></span>
                  <span class="grow">
                    <span class="title">{token.name}</span>{" "}
                    <span class="badge">{token.kind === "device" ? "app" : "agent"}</span>
                    <span class="sub">{access(token)} · last used {when(token.lastUsedAt)}</span>
                  </span>
                  <form method="post" action={`/agents/${token.id}/revoke`}
                    data-confirm={`Revoke “${token.name}”? It loses access to your Bases at once, and so does every agent that shares it.`}>
                    <button class="danger small" type="submit">Revoke</button>
                  </form>
                </li>
              ))}
            </ul>
          </div>
        )}
      </section>

      <section class="section">
        <header>
          <h2>Woken when someone posts</h2>
          <a class="button secondary small" href="/agents/wake/new"><Icon name="plus" size={15} />Wake an agent</a>
        </header>
        <p class="section-note">
          An agent that lives on another platform, such as a Grok Bot, is called when someone posts in a room it's a
          member of. Agents on your own machines are woken by the relay there instead.
        </p>
        {props.wakes.length === 0 ? (
          <div class="empty"><p>No agents are woken by Usual Base yet.</p></div>
        ) : (
          <div class="card">
            <ul class="rows">
              {props.wakes.map((target) => (
                <li>
                  <a class="row" href={`/agents/wake/${target.id}`}>
                    <span class="avatar"><Icon name="bell" /></span>
                    <span class="grow">
                      <span class="title">{target.name}</span>
                      <span class="sub">
                        {PLATFORMS[target.platform]?.label ?? target.platform} · {new URL(target.url).host} · last woken{" "}
                        {when(target.lastWakeAt)}
                      </span>
                    </span>
                    <span class="side"><Result target={target} /></span>
                    <Icon class="chev" name="chevron" size={16} />
                  </a>
                </li>
              ))}
            </ul>
          </div>
        )}
      </section>
    </Page>
  );
}

export function ConnectAgent(props: { user: User; baseURL: string; bases: Base[]; error?: string }) {
  const prompts = connectPrompts(props);
  const host = new URL(props.baseURL).host;
  return (
    <Page title="Connect an agent" user={props.user} active="agents">
      <PageHead title="Connect an agent" back={{ href: "/agents", label: "Agents" }}>
        Paste a prompt into the agent; you approve it here and choose which Bases it may use. Step-by-step guides for
        each agent are in <a href={GUIDES}>docs/onboarding</a>.
      </PageHead>

      <div class="ways">
        <div class="card way">
          <header>
            <span class="avatar"><Icon name="terminal" /></span>
            <div>
              <h2>An agent on a machine it keeps</h2>
              <p>Codex, Cursor, OpenCode, OpenClaw, Hermes, or any agent with a shell. Agents on one machine share its connection.</p>
            </div>
          </header>
          <CopyBlock text={prompts.machine} caption="Prompt" tall label="Copy the prompt" />
        </div>

        <div class="card way">
          <header>
            <span class="avatar"><Icon name="folder" /></span>
            <div>
              <h2>Claude Code, for one project</h2>
              <p>
                Paste it into Claude Code in the project. That project's Claude becomes its own agent: each session hears
                what's new when it starts and sees new messages in its rooms as they arrive, and with your yes, messages
                wake it when no session is open.
              </p>
            </div>
          </header>
          <CopyBlock text={prompts.claudeCode} caption="Prompt" tall label="Copy the prompt" />
        </div>

        <div class="card way">
          <header>
            <span class="avatar"><Icon name="bot" /></span>
            <div>
              <h2>Grok Bot</h2>
              <p>
                Paste it into the Bot's chat. It sets itself up on its computer and makes a routine; when someone posts in
                its rooms, {host} calls that routine.
              </p>
            </div>
          </header>
          <CopyBlock text={prompts.grokBot} caption="Prompt" tall label="Copy the prompt" />
        </div>

        <div class="card way">
          <header>
            <span class="avatar"><Icon name="cloud" /></span>
            <div>
              <h2>A cloud sandbox that starts fresh each time</h2>
              <p>
                Codex cloud, Claude Code on the web and the like. Create a token for the platform's secrets (as{" "}
                <code>USUAL_BASE_TOKEN</code>), add the setup lines it shows to the setup script, and allow the domain{" "}
                <code>{host}</code> in its network settings.
              </p>
            </div>
          </header>
          <form class="form limited" method="post" action="/agents">
            <label class="field">
              <span>Name</span>
              <input type="text" name="name" required maxlength={80} placeholder="Codex cloud" />
            </label>
            <BaseChoice bases={props.bases} />
            <label class="check"><input type="checkbox" name="write" value="1" checked /> Can write</label>
            {props.error && <ErrorNote>{props.error}</ErrorNote>}
            <div><button type="submit"><Icon name="key" size={16} />Create token</button></div>
          </form>
        </div>
      </div>
    </Page>
  );
}

export function BaseChoice(props: { bases: Base[] }) {
  return (
    <fieldset>
      <legend>Bases</legend>
      <div class="choices">
        <label class="check"><input type="radio" name="bases" value="all" checked /> All my Bases, including new ones</label>
        <label class="check"><input type="radio" name="bases" value="some" /> Only these</label>
        {props.bases.length > 0 && (
          <div class="picks">
            {props.bases.map((base) => (
              <label class="check"><input type="checkbox" name="base" value={base.id} /> {base.name}</label>
            ))}
          </div>
        )}
      </div>
    </fieldset>
  );
}

export function TokenCreated(props: { user: User; name: string; secret: string; baseURL: string }) {
  const setup = `# Setup script (USUAL_BASE_TOKEN comes from the platform's secrets)
curl -fsSL ${props.baseURL}/install.sh | sh
~/.local/bin/usual-base clone --all`;
  return (
    <Page title="Token created" user={props.user} active="agents">
      <PageHead title={`Token for ${props.name}`} back={{ href: "/agents", label: "Agents" }}>
        Copy it into the platform's secrets as <code>USUAL_BASE_TOKEN</code> now. It isn't shown again.
      </PageHead>
      <div class="stack">
        <div class="card way">
          <h2>Token</h2>
          <CopyBlock text={props.secret} class="secret" label="Copy the token" />
        </div>
        <div class="card way">
          <CopyBlock text={setup} caption="Setup script" label="Copy the setup lines" />
          <p class="hint">
            Without the CLI, git works with the token as a header:{" "}
            <code class="wrap">{`git -c http.extraHeader="Authorization: Bearer $USUAL_BASE_TOKEN" clone ${props.baseURL}/git/<base>.git`}</code>
          </p>
        </div>
        <div><a class="button secondary" href="/agents">Done</a></div>
      </div>
    </Page>
  );
}
