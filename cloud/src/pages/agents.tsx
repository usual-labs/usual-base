import type { Base } from "../bases";
import type { User } from "../env";
import type { TokenListing } from "../tokens";
import { Page, when } from "./layout";

function access(token: TokenListing) {
  const what = token.allBases ? "all Bases" : token.baseNames || "no Bases";
  return `${token.scope === "write" ? "read and write" : "read only"} · ${what}`;
}

export function AgentList(props: { user: User; tokens: TokenListing[] }) {
  return (
    <Page title="Agents and devices" user={props.user}>
      <div class="row">
        <h1>Agents and devices</h1>
        <a class="button" href="/agents/connect">Connect an agent</a>
      </div>
      <p class="muted">Each agent and device has its own token, so you can revoke one without the others.</p>
      {props.tokens.length === 0 ? (
        <p>Nothing connected yet.</p>
      ) : (
        <ul class="list card">
          {props.tokens.map((token) => (
            <li class="row">
              <span>
                <strong>{token.name}</strong> <span class="muted">({token.kind === "device" ? "device" : "agent"})</span>
                <br />
                <span class="muted">{access(token)} · last used {when(token.lastUsedAt)}</span>
              </span>
              <form method="post" action={`/agents/${token.id}/revoke`} style="margin:0">
                <button class="danger" type="submit">Revoke</button>
              </form>
            </li>
          ))}
        </ul>
      )}
    </Page>
  );
}

export function ConnectAgent(props: { user: User; baseURL: string; bases: Base[]; error?: string }) {
  const prompt = `Connect yourself to my Usual Base, a shared Markdown knowledge base that I read in the Usual Base app and my agents read and write as plain files.

1. Install the Usual Base CLI: curl -fsSL ${props.baseURL}/install.sh | sh
2. Run: usual-base connect --name "<your platform> on <this machine>"
   It prints a link and a code. Show them to me and wait while I approve; it then clones my Bases and installs the usual-base skill.
3. Add the lines it prints to your global instructions, show me what you added, and list the Bases you can read.`;
  return (
    <Page title="Connect an agent" user={props.user}>
      <h1>Connect an agent</h1>
      <h2>On a machine the agent keeps</h2>
      <p>Paste this into the agent. You approve it here, and choose which Bases it may use.</p>
      <pre>{prompt}</pre>

      <h2>In a cloud sandbox that starts fresh each time</h2>
      <p>
        Create a token for the platform's secret or environment settings (as <code>USUAL_BASE_TOKEN</code>), and add
        the setup lines below to its setup script. Allow the domain <code>{new URL(props.baseURL).host}</code> in its
        network settings.
      </p>
      <form class="stack" method="post" action="/agents">
        <label>Name<input type="text" name="name" required maxlength={80} placeholder="Codex cloud" /></label>
        <BaseChoice bases={props.bases} />
        <label class="inline"><input type="checkbox" name="write" value="1" checked /> Can write</label>
        {props.error && <p class="error">{props.error}</p>}
        <div><button type="submit">Create token</button></div>
      </form>
    </Page>
  );
}

export function BaseChoice(props: { bases: Base[] }) {
  return (
    <fieldset>
      <legend>Bases</legend>
      <label class="inline"><input type="radio" name="bases" value="all" checked /> All my Bases, including new ones</label>
      <label class="inline"><input type="radio" name="bases" value="some" /> Only these:</label>
      {props.bases.map((base) => (
        <label class="inline" style="margin-left:24px">
          <input type="checkbox" name="base" value={base.id} /> {base.name}
        </label>
      ))}
    </fieldset>
  );
}

export function TokenCreated(props: { user: User; name: string; secret: string; baseURL: string }) {
  const setup = `# Setup script (USUAL_BASE_TOKEN comes from the platform's secrets)
curl -fsSL ${props.baseURL}/install.sh | sh
~/.local/bin/usual-base clone --all`;
  return (
    <Page title="Token created" user={props.user}>
      <h1>Token for {props.name}</h1>
      <p>Copy it now. It isn't shown again.</p>
      <pre>{props.secret}</pre>
      <h2>Setup</h2>
      <pre>{setup}</pre>
      <p class="muted">
        Without the CLI, git works with the token as a header:{" "}
        <code>{`git -c http.extraHeader="Authorization: Bearer $USUAL_BASE_TOKEN" clone ${props.baseURL}/git/<base>.git`}</code>
      </p>
      <p><a href="/agents">Back to agents and devices</a></p>
    </Page>
  );
}
