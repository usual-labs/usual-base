import type { Base, PushRecord } from "../bases";
import type { User } from "../env";
import { Page, when } from "./layout";

export function BaseList(props: { user: User; bases: Base[] }) {
  return (
    <Page title="Bases" user={props.user}>
      <div class="row">
        <h1>Bases</h1>
        <a class="button" href="/bases/new">New Base</a>
      </div>
      {props.bases.length === 0 ? (
        <div class="card">
          <p>You have no Bases yet. A Base is a folder of Markdown notes shared with your agents.</p>
          <p>
            <a href="/bases/new">Create one</a>, or import a knowledge base you already have with the CLI:{" "}
            <code>usual import ./notes --name "Notes"</code> (see <a href="/agents/connect">Connect an agent</a>).
          </p>
        </div>
      ) : (
        <ul class="list card">
          {props.bases.map((base) => (
            <li class="row">
              <a href={`/bases/${base.id}`}><strong>{base.name}</strong></a>
              <span class="muted">
                {base.lastPushAt ? `changed ${when(base.lastPushAt)} by ${base.lastPushBy}` : "no changes yet"}
              </span>
            </li>
          ))}
        </ul>
      )}
    </Page>
  );
}

export function NewBase(props: { user: User; error?: string }) {
  return (
    <Page title="New Base" user={props.user}>
      <h1>New Base</h1>
      <form class="stack" method="post" action="/bases">
        <label>Name<input type="text" name="name" required maxlength={80} placeholder="Notes" /></label>
        {props.error && <p class="error">{props.error}</p>}
        <div><button type="submit">Create</button></div>
      </form>
    </Page>
  );
}

export function BaseDetail(props: { user: User; base: Base; git: string; pushes: PushRecord[]; error?: string }) {
  const { base } = props;
  return (
    <Page title={base.name} user={props.user}>
      <h1>{base.name}</h1>
      <p class="muted">Created {when(base.createdAt)} · last change {when(base.lastPushAt)}</p>

      <h2>Use it</h2>
      <div class="card">
        <p>
          <strong>Mac app:</strong> sign in, and the Base appears in the sidebar.
        </p>
        <p>
          <strong>Agents:</strong> <a href="/agents/connect">connect an agent</a>; it clones every Base its token
          allows.
        </p>
        <p><strong>Git:</strong> clone with a Usual Base token as the password.</p>
        <pre>{`git clone ${props.git}`}</pre>
      </div>

      <h2>Recent pushes</h2>
      {props.pushes.length === 0 ? (
        <p class="muted">Nothing pushed yet.</p>
      ) : (
        <ul class="list card">
          {props.pushes.map((push) => (
            <li class="row">
              <span>{push.tokenName}</span>
              <span class="muted"><code>{push.newId.slice(0, 7)}</code> · {when(push.at)}</span>
            </li>
          ))}
        </ul>
      )}

      <h2>Settings</h2>
      <form class="stack" method="post" action={`/bases/${base.id}/rename`}>
        <label>Name<input type="text" name="name" required maxlength={80} value={base.name} /></label>
        <div><button class="secondary" type="submit">Rename</button></div>
      </form>
      <form class="stack" method="post" action={`/bases/${base.id}/delete`} style="margin-top:24px">
        <label>
          Delete this Base and all its history. Type its name to confirm.
          <input type="text" name="confirm" required autocomplete="off" />
        </label>
        {props.error && <p class="error">{props.error}</p>}
        <div><button class="danger" type="submit">Delete Base</button></div>
      </form>
    </Page>
  );
}
